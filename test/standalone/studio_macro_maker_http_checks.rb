require "active_record"
require "action_controller/railtie"
require "rack/mock"
require "tmpdir"
require "securerandom"
require "open3"

ROOT = File.expand_path("../..", __dir__)
require File.join(ROOT, "app/services/studio/composition")
require File.join(ROOT, "app/services/studio/macro_maker/composition_store")
require File.join(ROOT, "app/services/studio/macro_maker/serializer")

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class User < ApplicationRecord; end

module DymondSite
  class Site < ApplicationRecord
    self.table_name = "dymond_site_sites"
  end
end

require File.join(ROOT, "app/models/studio/operation_record")
require File.join(ROOT, "db/migrate/20261125153000_create_studio_operation_records")
require File.join(ROOT, "db/migrate/20261125154000_add_owner_to_studio_operation_records")
%w[base catalog compositions operations].each do |name|
  require File.join(ROOT, "app/controllers/studio/macro_maker/#{name}_controller")
end

class MacroMakerTestApplication < Rails::Application
  config.root = Dir.mktmpdir("studio-macro-rails-")
  config.eager_load = false
  config.secret_key_base = "macro-maker-fixture-secret"
  config.logger = Logger.new(File::NULL)
  config.hosts.clear
end

Rails.application.initialize!
Rails.application.routes.draw do
  path = File.join(ROOT, "config/routes/studio_macro_maker.rb")
  instance_eval(File.read(path), path)
end
def Rails.root = Pathname.new(ROOT)

def assert(value, message)
  raise message unless value
end

PREFIX = "/api/v1/studio/macro_maker"
RESPONSES = []
def request(context, method, path, schema, status, payload = nil)
  env = Rack::MockRequest.env_for("#{PREFIX}#{path}", method: method,
    "HTTP_ACCEPT" => "application/json", "CONTENT_TYPE" => "application/json",
    input: payload ? JSON.generate(payload) : "")
  env[Studio::MacroMaker::BaseController::CONTEXT_KEY] = context
  code, headers, body = Rails.application.call(env)
  contents = +""
  begin
    body.each { |part| contents << part }
  ensure
    body.close if body.respond_to?(:close)
  end
  assert(code == status, "#{method} #{path} returned #{code}, expected #{status}: #{contents[0, 600]}")
  assert(headers["cache-control"]&.include?("no-store"), "Response can be cached across callers")
  json = JSON.parse(contents)
  RESPONSES << {"schema" => schema, "body" => json, "request" => "#{method} #{path}"}
  json
end

adapters = Studio::Operation::Thin::SURFACES.keys.to_h do |engine|
  [engine, Studio::Operation::EngineAdapter.new(engine: engine, executable: ENV.fetch("#{engine.upcase}_CLI"))]
end
ActiveRecord::Base.establish_connection(ENV.fetch("STUDIO_RECIPE_TEST_DATABASE_URL"))
connection = ActiveRecord::Base.connection
schema = "studio_macro_http_#{SecureRandom.hex(8)}"
connection.execute("CREATE SCHEMA #{schema}")
begin
  connection.schema_search_path = schema
  connection.create_table(:dymond_site_sites)
  connection.create_table(:users)
  ActiveRecord::Migration.verbose = false
  CreateStudioOperationRecords.new.migrate(:up)
  AddOwnerToStudioOperationRecords.new.migrate(:up)
  site = DymondSite::Site.create!
  other_site = DymondSite::Site.create!
  user = User.create!
  teammate = User.create!
  context = {site: site, user: user, engine_adapters: adapters}
  peer = context.merge(user: teammate)
  foreign = context.merge(site: other_site)
  unavailable = adapters.merge("photocraft" => Studio::Operation::EngineAdapter.new(engine: "photocraft", executable: nil))
  offline = context.merge(engine_adapters: unavailable)
  hair = "studio.add_facial_hair"
  macro = "studio.double_beard"

  initial = request(context, "GET", "/catalog", "catalog", 200)
  items = initial.fetch("thick_operations").to_h { |row| [row.fetch("id"), row] }
  assert(items.keys.sort == [hair, "studio.animate_layer_position", "studio.set_layer_opacity"], "Unexpected catalog operations")
  assert(items.fetch(hair).dig("params_schema", "properties", "position", "studio_type") == "point" &&
      items.fetch(hair).dig("inputs_schema", "properties", "mask_path", "studio_type") == "polygon" &&
      items.fetch(hair).dig("returns", "hair_layer") == "layer_id" &&
      items.fetch(hair).fetch("applicable_context") == ["active_selection"], "Image catalog metadata is incomplete")
  assert(items.fetch("studio.animate_layer_position").fetch("applicable_context") == %w[open_composition timeline_playhead],
    "Catalog did not union motion requirements")
  filtered = request(context, "GET", "/catalog?surface=image", "catalog", 200)
  assert(filtered.fetch("thick_operations").map { |row| row["id"] } == [hair, "studio.set_layer_opacity"], "Catalog surface filter failed")

  source = YAML.safe_load_file(File.join(ROOT, "config/studio/operations/add_facial_hair.yml"))
  Studio::OperationRecord.create!(site: site, operation_id: hair, surface: "image", version: 2,
    body: source.merge("display_name" => "Tenant Facial Hair"), published: true)
  shown = request(context, "GET", "/catalog?surface=image", "catalog", 200).fetch("thick_operations")
  assert(shown.find { |row| row["id"] == hair }.fetch("origin") == "tenant", "Tenant operation did not take the menu slot")
  shown = request(foreign, "GET", "/catalog?surface=image", "catalog", 200).fetch("thick_operations")
  assert(shown.find { |row| row["id"] == hair }.fetch("origin") == "builtin", "Catalog crossed site boundary")

  definition = {"id" => macro, "name" => "Double Beard", "surface" => "image", "description" => "Add two layered effects.",
    "steps" => [{"operation" => hair, "returns" => {"first_beard" => "hair_layer"}}, {"operation" => hair}]}
  payload = {"definition" => definition}
  count = Studio::OperationRecord.count
  draft_result = request(context, "POST", "/validate", "validation", 200, payload)
  assert(draft_result.fetch("valid") && draft_result.fetch("warnings").empty?, "Valid chain failed")
  assert(draft_result.dig("compiled_recipe", "steps").size > 2, "Thick calls did not expand")
  assert(Studio::OperationRecord.count == count, "Draft validation wrote a record")
  warnings = request(offline, "POST", "/validate", "validation", 200, payload).fetch("warnings")
  assert(warnings.map { |item| item["step_index"] } == [0, 1], "Offline steps did not warn")

  bad = definition.merge("steps" => [definition.fetch("steps").first,
    {"operation" => hair, "inputs" => {"mask_path" => {"$ref" => "absent"}}}])
  bad_payload = {"definition" => bad}
  bad_validation = request(context, "POST", "/validate", "errors", 422, bad_payload)
  assert(bad_validation.dig("errors", 0, "step_index") == 1 &&
    bad_validation.dig("errors", 0, "kind") == "unresolved_ref", "Validation lost structured step errors")
  assert(request(context, "POST", "/compositions", "errors", 422, bad_payload) == bad_validation,
    "Save and validation do not share an error envelope")
  assert(Studio::OperationRecord.count == count, "Failed save wrote a record")
  thin = {"definition" => definition.merge("steps" => [{"operation" => "photocraft:layer.new.layer"}])}
  assert(request(context, "POST", "/validate", "errors", 422, thin).dig("errors", 0, "kind") == "unknown_operation",
    "v1 accepted a directly wired thin command")

  first = request(context, "POST", "/compositions", "created", 201, payload.merge("published" => true))
  second = request(context, "POST", "/compositions", "created", 201, payload.merge("published" => true))
  draft = request(context, "POST", "/compositions", "created", 201, payload.merge("published" => false, "site_id" => other_site.id))
  assert([first, second, draft].map { |row| row.fetch("version") } == [1, 2, 3], "Server did not allocate consecutive versions")
  assert(draft.fetch("published") == false && Studio::OperationRecord.find(draft.fetch("id")).site_id == site.id,
    "Draft visibility or trusted site context failed")

  mine = request(context, "GET", "/compositions?surface=image", "composition_list", 200).fetch("compositions")
  theirs = request(peer, "GET", "/compositions?surface=image", "composition_list", 200).fetch("compositions")
  assert(mine.map { |row| row.fetch("version") } == [3, 2] && theirs.map { |row| row.fetch("version") } == [2],
    "List did not retain current publication and only the caller's drafts")
  assert(mine.first.dig("definition", "steps") == definition.fetch("steps"), "List omitted source steps")
  assert(request(foreign, "GET", "/compositions?surface=image", "composition_list", 200).fetch("compositions").empty?,
    "List leaked records across sites")

  detail = request(context, "GET", "/compositions/#{macro}?surface=image", "composition_detail", 200)
  assert(detail.fetch("version") == 3 && detail.dig("definition", "steps") == definition.fetch("steps") &&
    detail.dig("compiled_recipe", "steps").size > 2 && detail.fetch("references").size == 2 &&
    detail.dig("returns", "first_beard") == "layer_id", "Saved detail did not reopen source composition")
  assert(request(peer, "GET", "/compositions/#{macro}?surface=image", "composition_detail", 200).fetch("version") == 2,
    "Another user's draft was returned")
  request(foreign, "GET", "/compositions/#{macro}?surface=image", "errors", 404)

  operation = request(context, "GET", "/operations/#{macro}?surface=image", "operation_detail", 200)
  assert(operation.fetch("version") == 2 && operation["runnable"] &&
    (operation.keys & %w[recipe compiled_recipe definition references]).empty?, "Run form disclosed internals or selected a draft")
  assert(!request(offline, "GET", "/operations/#{macro}?surface=image", "operation_detail", 200).fetch("runnable"),
    "Run form did not reflect the missing CLI")
  request(foreign, "GET", "/operations/#{macro}?surface=image", "errors", 404)
  request(context, "GET", "/operations/photocraft:layer.new.layer?surface=image", "errors", 404)
  request(context, "GET", "/catalog?surface=unknown", "errors", 422)
  request(nil, "GET", "/catalog", "errors", 403)

  concurrent_payload = {"definition" => definition.merge("id" => "studio.concurrent"), "published" => true}
  gate = Queue.new
  ready = Queue.new
  saves = 2.times.map do
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |thread_connection|
        thread_connection.schema_search_path = schema
        identity = context.merge(site: DymondSite::Site.find(site.id), user: User.find(user.id))
        ready << true
        gate.pop
        request(identity, "POST", "/compositions", "created", 201, concurrent_payload).fetch("version")
      ensure
        thread_connection.schema_search_path = "public"
      end
    end
  end
  2.times { ready.pop }
  2.times { gate << true }
  assert(saves.map(&:value).sort == [1, 2], "Concurrent saves collided on a version")

  schema_file = File.join(ROOT, Studio::MacroMaker::Serializer::SCHEMA_PATH)
  validation = <<~PYTHON
    import json, sys
    from pathlib import Path
    from jsonschema import Draft202012Validator
    from referencing import Registry, Resource
    directory = Path(sys.argv[1]).parent
    schema = json.loads(Path(sys.argv[1]).read_text())
    Draft202012Validator.check_schema(schema)
    registry = Registry().with_resource("recipe.schema.json", Resource.from_contents(
        json.loads((directory / "recipe.schema.json").read_text())))
    for response in json.load(sys.stdin):
        contract = {"$schema": schema["$schema"], "$defs": schema["$defs"], "$ref": "#/$defs/" + response["schema"]}
        validator = Draft202012Validator(contract, registry=registry, format_checker=Draft202012Validator.FORMAT_CHECKER)
        try:
            validator.validate(response["body"])
        except Exception as failure:
            raise ValueError(response["request"]) from failure
  PYTHON
  _, stderr, status = Open3.capture3("python3", "-c", validation, schema_file, stdin_data: JSON.generate(RESPONSES))
  assert(status.success?, stderr)
  puts "PASS #{RESPONSES.length} schema-validated HTTP responses, versioning, owner-only drafts, offline warnings and site isolation"
ensure
  connection.schema_search_path = "public"
  connection.execute("DROP SCHEMA #{schema} CASCADE")
end
