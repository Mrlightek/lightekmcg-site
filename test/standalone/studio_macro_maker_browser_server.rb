require_relative "../support/studio_recipe_fixture"
require "active_record"
require "active_storage/engine"
require "active_job/railtie"
require "action_cable/engine"
require "digest"
require "open3"
require "rbconfig"
require "action_controller/railtie"
require "turbo-rails"
require "rackup/handler/webrick"
require "securerandom"
require "tmpdir"

ROOT = File.expand_path("../..", __dir__)
require File.join(ROOT, "app/services/studio/composition")
require File.join(ROOT, "app/services/studio/macro_maker/composition_store")
require File.join(ROOT, "app/services/studio/macro_maker/serializer")

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
class User < ApplicationRecord; end
class ApplicationController < ActionController::Base; end
module DymondSite
  class Site < ApplicationRecord
    self.table_name = "dymond_site_sites"
  end
end
require File.join(ROOT, "app/models/studio/operation_record")
require File.join(ROOT, "app/jobs/application_job")
require File.join(ROOT, "app/jobs/studio/macro_maker/motion_run_job")
require File.join(ROOT, "app/services/studio/macro_maker/effect_craft_renderer")
require File.join(ROOT, "app/services/studio/macro_maker/runner")
require File.join(ROOT, "app/services/studio/macro_maker/editor_export")
require File.join(ROOT, "app/services/studio/macro_maker/effect_craft_export")
require File.join(ROOT, "db/migrate/20260630151924_create_active_storage_tables.active_storage")
require File.join(ROOT, "db/migrate/20261125155000_create_studio_render_results")
require File.join(ROOT, "db/migrate/20261125153000_create_studio_operation_records")
require File.join(ROOT, "db/migrate/20261125154000_add_owner_to_studio_operation_records")
require File.join(ROOT, "app/helpers/studio/macro_maker/form_helper")
require File.join(ROOT, "app/controllers/studio/macro_maker/base_controller")
require File.join(ROOT, "app/controllers/concerns/studio_blob_streaming")
require File.join(ROOT, "app/controllers/studio/macro_maker/workspace_controller")
require File.join(ROOT, "app/controllers/studio/macro_maker/editor_controller")
require File.join(ROOT, "app/controllers/studio/macro_maker/runs_controller")
require File.join(ROOT, "app/controllers/studio/macro_maker/editor_features_controller")

class MacroMakerBrowserApplication < Rails::Application
  config.root = Dir.mktmpdir("studio-macro-browser-")
  config.eager_load = false
  config.secret_key_base = "macro-maker-browser-fixture-secret"
  config.logger = Logger.new(File::NULL)
  config.hosts.clear
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = true
  config.active_job.queue_adapter = :test
  config.action_cable.cable = {"adapter" => "test"}
  config.active_storage.service = :test
  config.active_storage.service_configurations = {test: {service: "Disk", root: config.root.join("storage").to_s}}
end

ENV["DATABASE_URL"] ||= ENV.fetch("STUDIO_RECIPE_TEST_DATABASE_URL")
Rails.application.initialize!
Rails.application.routes.draw do
  route_file = File.join(ROOT, "config/routes/studio_macro_maker.rb")
  instance_eval(File.read(route_file), route_file)
end
def Rails.root = Pathname.new(ROOT)
Studio::MacroMaker::RunsController.include(Rails.application.routes.url_helpers)
ApplicationController.helper(Rails.application.routes.url_helpers)
Studio::MacroMaker::WorkspaceController.helper(Rails.application.routes.url_helpers)
ApplicationController.helper { def default_url_options = {} }
Studio::MacroMaker::WorkspaceController.helper { def default_url_options = {} }

modules = {
  "@hotwired/stimulus" => [Gem.loaded_specs.fetch("stimulus-rails").full_gem_path, "app/assets/javascripts/stimulus.min.js"],
  "turbo" => [Gem.loaded_specs.fetch("turbo-rails").full_gem_path, "app/assets/javascripts/turbo.min.js"],
  "composition_editor" => [ROOT, "app/javascript/controllers/composition_editor_controller.js"],
  "step_list" => [ROOT, "app/javascript/controllers/step_list_controller.js"],
  "form_values" => [ROOT, "app/javascript/macro_maker/form_values.js"],
  "motion_run_status" => [ROOT, "app/javascript/controllers/motion_run_status_controller.js"],
  "studio_editor_relay" => [ROOT, "app/javascript/controllers/studio_editor_relay_controller.js"],
  "macro_run" => [ROOT, "app/javascript/controllers/macro_run_controller.js"],
  "handle_binding" => [ROOT, "app/javascript/controllers/handle_binding_controller.js"]
}
layout = <<~ERB
  <!doctype html><html><head>
    <meta charset="utf-8"><%= csrf_meta_tags %><%= yield :head %>
    <script type="importmap">{"imports":{"@hotwired/stimulus":"/browser-assets/@hotwired/stimulus.js","macro_maker/form_values":"/browser-assets/form_values.js"}}</script>
    <script type="module" src="/browser-assets/application.js"></script>
  </head><body><%= yield %></body></html>
ERB
resolver = ActionView::FileSystemResolver.new(File.join(ROOT, "app/views"))
path = Rails.application.config.root.join("fixture_views")
FileUtils.mkdir_p(path.join("layouts"))
File.write(path.join("layouts/application.html.erb"), layout)
Studio::MacroMaker::WorkspaceController.prepend_view_path([ActionView::FileSystemResolver.new(path.to_s), resolver])
ApplicationController.prepend_view_path(resolver)
application = <<~JS
  import "/browser-assets/turbo.js"
  import { Application } from "@hotwired/stimulus"
  import CompositionEditor from "/browser-assets/composition_editor.js"
  import StepList from "/browser-assets/step_list.js"
  import MotionRunStatus from "/browser-assets/motion_run_status.js"
  import StudioEditorRelay from "/browser-assets/studio_editor_relay.js"
  import MacroRun from "/browser-assets/macro_run.js"
  import HandleBinding from "/browser-assets/handle_binding.js"
  const app = Application.start()
  app.register("composition-editor", CompositionEditor)
  app.register("step-list", StepList)
  app.register("handle-binding", HandleBinding)
  app.register("macro-run", MacroRun)
  app.register("studio-editor-relay", StudioEditorRelay)
  app.register("motion-run-status", MotionRunStatus)
JS

ActiveRecord::Base.establish_connection(ENV.fetch("STUDIO_RECIPE_TEST_DATABASE_URL"))
connection = ActiveRecord::Base.connection
schema = "studio_ui_#{SecureRandom.hex(8)}"
connection.execute("CREATE SCHEMA #{schema}")
connection.schema_search_path = schema
connection.create_table(:dymond_site_sites)
connection.create_table(:users)
ActiveRecord::Migration.verbose = false
CreateStudioOperationRecords.new.migrate(:up)
AddOwnerToStudioOperationRecords.new.migrate(:up)
CreateActiveStorageTables.new.migrate(:up)
CreateStudioRenderResults.new.migrate(:up)
require File.join(ROOT, "app/models/studio/render_result")
site = DymondSite::Site.create!
user = User.create!
site_id = site.id
user_id = user.id
foreign_site_id = DymondSite::Site.create!.id
foreign_user_id = User.create!.id
module LightekPwa
  class Policy
    class << self
      attr_accessor :site_by_user
    end
    def self.sites_for(user) = DymondSite::Site.where(id: site_by_user[user.id])
  end
end
LightekPwa::Policy.site_by_user = {user_id => site_id, foreign_user_id => foreign_site_id}
adapters = Studio::Operation::Thin::SURFACES.keys.to_h do |engine|
  [engine, Studio::Operation::EngineAdapter.new(engine: engine, executable: ENV.fetch("#{engine.upcase}_CLI"))]
end

options = {engine_adapters: adapters}
definition = {
  "id" => "studio.run_proof", "name" => "Run Proof", "surface" => "image", "description" => "Adjust the proof image.",
  "parameters" => {"opacity" => {"type" => "number", "min" => 0, "max" => 1, "default" => 0.5}},
  "steps" => [{"operation" => "studio.set_layer_opacity", "params" => {"opacity" => {"$param" => "opacity"}},
    "inputs" => {"layer" => 2}}]
}
store = Studio::MacroMaker::CompositionStore.new(site: site, user: user, catalog_options: options)
store.create!(definition, published: true)
store.create!(definition.merge("name" => "Unpublished Revision"), published: false)
store.create!(definition.merge("id" => "studio.draft_only"), published: false)
motion = {
  "id" => "studio.motion_run_proof", "display_name" => "Motion Run Proof", "surface" => "motion",
  "description" => "Create a new composition.", "exposes" => [],
  "recipe" => {"name" => "Motion Run Proof", "version" => 1, "engine" => "effectcraft", "parameters" => {},
    "steps" => [{"command" => "comp.new", "params" => {"name" => "Run Proof", "width" => 32, "height" => 32}}]}
}
Studio::OperationRecord.create!(site: site, operation_id: motion.fetch("id"), surface: "motion",
  published: true, version: 1, body: motion)

if ENV["STUDIO_PHOTOCRAFT_EDITOR_URL"]
  assets_motion = motion.deep_dup
  assets_motion["id"] = "studio.motion_assets_proof"
  assets_motion["display_name"] = "Motion Assets Proof"
  assets_motion["recipe"]["steps"] = [{"command" => "comp.settings", "params" => {"name" => "Rendered editor comp"}}]
  Studio::OperationRecord.create!(site: site, operation_id: assets_motion.fetch("id"), surface: "motion",
    published: true, version: 1, body: assets_motion)
  gated = {
    "id" => "studio.selection_run_proof", "display_name" => "Selection Proof", "surface" => "image",
    "description" => "Draw a test selection.", "exposes" => [],
    "recipe" => {"name" => "Selection Proof", "version" => 1, "engine" => "photocraft", "parameters" => {},
      "steps" => [{"command" => "select.lasso", "params" => {"points" => [[1, 1], [15, 1], [15, 12]], "polygonal" => true}}]}
  }
  Studio::OperationRecord.create!(site: site, operation_id: gated.fetch("id"), surface: "image", published: true, version: 1, body: gated)
  if ENV["STUDIO_PHOTOCRAFT_BRIDGE_TEST"]
    fill = gated.deep_dup
    fill["id"] = "studio.selection_fill_proof"
    fill["display_name"] = "Selection Fill Proof"
    fill.fetch("recipe").fetch("steps").unshift({"command" => "edit.fill", "params" => {"contents" => "color", "color" => "#ff00ff"}})
    Studio::OperationRecord.create!(site: site, operation_id: fill.fetch("id"), surface: "image",
      published: true, version: 1, body: fill)
  end
  foreign_body = Marshal.load(Marshal.dump(gated))
  foreign_body["id"] = "studio.foreign_feature"
  Studio::OperationRecord.create!(site_id: foreign_site_id, operation_id: foreign_body.fetch("id"), surface: "image",
    published: true, version: 1, body: foreign_body)
end

failure_cli = Rails.application.config.root.join("failing-photocraft")
File.write(failure_cli, "#!#{RbConfig.ruby} --disable-gems\n" + <<~'ENGINE')
  require "json"
  $stdout.sync = true
  STDIN.each_line do |line|
    message = JSON.parse(line)
    if message["method"] == "engine.execute"
      warn "fixture engine failure"
      puts JSON.generate(id: message["id"], ok: false, error: "fixture rejected command")
    else
      puts JSON.generate(id: message["id"], ok: true, result: {})
    end
  end
ENGINE
File.chmod(0o700, failure_cli)
failure_adapters = adapters.merge("photocraft" => Studio::Operation::EngineAdapter.new(engine: "photocraft", executable: failure_cli.to_s))

motion_cli = Rails.application.config.root.join("failing-effectcraft")
File.write(motion_cli, <<~SH)
  #!/bin/sh
  if [ "$1" = render ]; then
    if [ "$STUDIO_MOTION_FIXTURE_MODE" = timeout ]; then
      echo 'progress 1 4 0.3 0.9' >&2
      exec sleep 60
    fi
    echo 'fixture video encoder failed' >&2
    exit 1
  fi
  exec "#{adapters.fetch("effectcraft").executable}" "$@"
SH
File.chmod(0o700, motion_cli)

browser_app = lambda do |env|
  path = env.fetch("PATH_INFO")
  if path == "/stylesheets/studio_macro_maker.css"
    next [200, {"content-type" => "text/css"}, [File.read(File.join(ROOT, "app/assets/stylesheets/studio_macro_maker.css"))]]
  end
  if path.start_with?("/browser-assets/")
    key = path.delete_prefix("/browser-assets/").delete_suffix(".js")
    body = key == "application" ? application : File.read(File.join(*modules.fetch(key)))
    next [200, {"content-type" => "text/javascript"}, [body]]
  end

  ActiveRecord::Base.connection_pool.with_connection do |request_connection|
    request_connection.schema_search_path = schema
    if path == "/browser-check"
      record = Studio::OperationRecord.where(site_id: site_id, operation_id: "studio.browser_proof").order(version: :desc).first
      next [200, {"content-type" => "application/json"}, [JSON.generate(record&.body)]]
    end

    if path == "/studio-fixture.png"
      next [200, {"content-type" => "image/png"}, [File.binread(StudioRecipeFixture.path)]]
    end

    if path == "/run-fixture-check"
      runs = Studio::RenderResult.order(:id)
      next [200, {"content-type" => "application/json"}, [JSON.generate({
        runs: runs.map { |run| run.attributes.slice("id", "status", "error_message", "operation_record_id", "version", "input_filename") },
        temporary_inputs: Dir.glob(File.join(Dir.tmpdir, "studio-macro-run-*")).size
      })]]
    end
    if path == "/run-fixture-perform"
      job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |entry| entry[:job] == Studio::MacroMaker::MotionRunJob }
      raise "No motion job enqueued" unless job
      ActiveJob::Base.queue_adapter.enqueued_jobs.delete(job)
      mode = env["HTTP_X_FIXTURE_RENDER"]
      previous_cli = ENV["STUDIO_EFFECTCRAFT_CLI"]
      previous_timeout = ENV["STUDIO_EFFECTCRAFT_RENDER_TIMEOUT_SECONDS"]
      begin
        ENV["STUDIO_EFFECTCRAFT_CLI"] = case mode
        when "recipe" then "#{motion_cli}-missing"
        when "failure", "timeout" then motion_cli.to_s
        else adapters.fetch("effectcraft").executable
        end
        ENV["STUDIO_MOTION_FIXTURE_MODE"] = mode
        ENV["STUDIO_EFFECTCRAFT_RENDER_TIMEOUT_SECONDS"] = "2" if mode == "timeout"
        ActiveJob::Base.execute(job)
      ensure
        ENV["STUDIO_EFFECTCRAFT_CLI"] = previous_cli
        ENV["STUDIO_EFFECTCRAFT_RENDER_TIMEOUT_SECONDS"] = previous_timeout
        ENV.delete("STUDIO_MOTION_FIXTURE_MODE")
      end
      run = Studio::RenderResult.find(job[:args].first)
      stream_name = Turbo::StreamsChannel.send(:stream_name_from, [run])
      broadcasts = ActionCable.server.pubsub.broadcasts(stream_name).map { |entry| JSON.parse(entry) }
      project_reopened = if run.source_project.attached?
        run.source_project.open(tmpdir: Rails.application.config.root) do |file|
          _stdout, _stderr, status = Open3.capture3(adapters.fetch("effectcraft").executable, "info",
            "--project", file.path, "--json")
          status.success?
        end
      end
      fixture_result = run.attributes.slice("id", "status", "error_message").merge(
        video: run.output.attached?, project: run.source_project.attached?, staged_input: run.editor_input.attached?, staged_assets: run.editor_assets.attached?, reopened: project_reopened, broadcasts: broadcasts)
      next [200, {"content-type" => "application/json"}, [JSON.generate(fixture_result)]]
    end

    if path == "/apply-fixture-photo"
      fixture = Studio::Recipe.new(gated.fetch("recipe"))
      bytes = Dir.mktmpdir do |directory|
        output = File.join(directory, "selection.pcraft")
        fixture.run!(executable: adapters.fetch("photocraft").executable,
          input: StudioRecipeFixture.path, output: output)
        File.binread(output)
      end
      next [200, {"content-type" => "application/octet-stream"}, [bytes]]
    end

    if path == "/run-fixture-direct"
      request_site = DymondSite::Site.find(site_id)
      operation = Studio::OperationCatalog.find(request_site, "studio.run_proof", surface: "image", **options)
      hash = Dir.mktmpdir do |directory|
        output = File.join(directory, "direct.png")
        operation.recipe.run!(executable: adapters.fetch("photocraft").executable,
          input: StudioRecipeFixture.path, output: output, parameters: {"opacity" => 0.35})
        Digest::SHA256.file(output).hexdigest
      end
      next [200, {"content-type" => "text/plain"}, [hash]]
    end

    env[Studio::MacroMaker::BaseController::CONTEXT_KEY] = {
      site: DymondSite::Site.find(env["HTTP_X_FIXTURE_SITE"] == "foreign" ? foreign_site_id : site_id),
      user: User.find(env["HTTP_X_FIXTURE_USER"] == "foreign" ? foreign_user_id : user_id), engine_adapters: env["HTTP_X_FIXTURE_ENGINE"] == "broken" ? failure_adapters : adapters
    }
    Rails.application.call(env)
  end
end

begin
  Rackup::Handler::WEBrick.run(browser_app, Host: "127.0.0.1", Port: Integer(ENV.fetch("STUDIO_MACRO_BROWSER_PORT", "41193")))
ensure
  connection.schema_search_path = "public"
  connection.execute("DROP SCHEMA #{schema} CASCADE")
end
