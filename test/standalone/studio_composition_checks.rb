require_relative "../support/studio_recipe_fixture"
require "active_record"
require "securerandom"
require "tmpdir"
require_relative "../../app/services/studio/composition"

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

module DymondSite
  class Site < ApplicationRecord
    self.table_name = "dymond_site_sites"
  end
end

require_relative "../../app/models/studio/operation_record"
require_relative "../../db/migrate/20261125153000_create_studio_operation_records"

def assert(condition, message)
  raise message unless condition
end

def invalid(kind, index, id, includes: [])
  yield
  raise "Expected #{kind} at step #{index}"
rescue Studio::Composition::Invalid => error
  match = error.errors.find do |item|
    item[:kind] == kind && item[:step_index] == index && item[:step_operation_id] == id
  end
  assert(match && includes.all? { |text| match.fetch(:detail).include?(text) }, error.errors.inspect)
  error
end

root = File.expand_path("../..", __dir__)
built_ins = File.join(root, "config/studio/operations")
metadata = File.join(root, "config/studio/command_schemas")
character = StudioRecipeFixture.path
adapters = Studio::Operation::Thin::SURFACES.keys.to_h do |engine|
  [engine, Studio::Operation::EngineAdapter.new(engine: engine, executable: ENV.fetch("#{engine.upcase}_CLI"))]
end

ActiveRecord::Base.establish_connection(ENV.fetch("STUDIO_RECIPE_TEST_DATABASE_URL"))
connection = ActiveRecord::Base.connection
schema = "studio_composition_test_#{SecureRandom.hex(8)}"
connection.execute("CREATE SCHEMA #{schema}")
begin
  connection.schema_search_path = schema
  connection.create_table(:dymond_site_sites)
  ActiveRecord::Migration.verbose = false
  CreateStudioOperationRecords.new.migrate(:up)
  site = DymondSite::Site.create!
  other_site = DymondSite::Site.create!

  Dir.mktmpdir("studio-composition-") do |directory|
    options = {engine_adapters: adapters, built_in_directory: built_ins, command_schema_directory: directory}
    %w[photocraft effectcraft].each do |engine|
      File.write(File.join(directory, "#{engine}.yml"), File.read(File.join(metadata, "#{engine}.yml")))
    end
    photo_file = File.join(directory, "photocraft.yml")
    original_photo = File.read(photo_file)
    create = {"operation" => "photocraft:layer.new.layer", "params" => {"name" => {"$param" => "layerName"}},
      "returns" => {"base_layer" => "layer"}}
    change = {"operation" => "photocraft:layer.setProps",
      "params" => {"layer" => {"$ref" => "base_layer"}, "opacity" => 0.5}}
    definition = {"id" => "studio.layer_workflow", "name" => "Layer Workflow", "version" => 1, "surface" => "image",
      "description" => "Create a layer and adjust it.",
      "parameters" => {"layerName" => {"type" => "string", "default" => "Macro Layer"}},
      "steps" => [create, change]}
    make = ->(changes = {}) { Studio::Composition.new(site: site, definition: definition.merge(changes), catalog_options: options) }

    composition = make.call
    compiled = composition.to_recipe
    compiled_body = JSON.parse(compiled.to_json)
    assert(compiled_body.fetch("steps")[1]["params"]["layer"] == {"$ref" => "base_layer"}, "Compile lost the handle")
    assert(compiled_body.fetch("parameters") == definition.fetch("parameters"), "Compile lost parameters")
    record = composition.save!(published: true)
    persisted = record.reload.body
    assert(persisted.dig("composition", "definition") == definition, "Source composition failed to round trip")
    assert(persisted.dig("composition", "references").map { |item| item.fetch("id") } == [create, change].map { |s| s["operation"] },
      "Saved references are incomplete")
    assert(persisted.fetch("recipe") == compiled_body, "Stored recipe differs from compiled recipe")
    entry = Studio::OperationCatalog.for_site(site, **options).find { |op| op.id == record.operation_id }
    assert(entry&.origin == :tenant && entry.returns == {"base_layer" => "layer_id"}, "Saved composition missing from tenant catalog")
    stored = Studio::Composition.from_record(record, catalog_options: options)
    assert(stored.verify!(persisted.fetch("recipe"), persisted.dig("composition", "references")), "Round trip failed validation")

    photo = adapters.fetch("photocraft").executable
    output = File.join(directory, "compiled.pcraft")
    compiled.run!(executable: photo, input: character, output: output, parameters: {"layerName" => "Runtime Layer"})
    stdout, status = Open3.capture2(photo, "info", output)
    assert(status.success?, "Could not inspect the output")
    layer = JSON.parse(stdout).fetch("layers").find { |item| item["name"] == "Runtime Layer" }
    assert(layer && layer["opacity"] == 0.5, "The second step did not modify the layer from the first")
    entry.run!(input: character, output: File.join(directory, "catalog.pcraft"))

    make.call("id" => "studio.three_steps", "steps" => [create,
      {"operation" => "photocraft:layer.new.layer", "params" => {"name" => "Other Layer"}}, change]).save!

    unresolved = change.merge("params" => {"layer" => {"$ref" => "missing"}, "opacity" => {"$input" => "missing_input"}})
    fail_count = Studio::OperationRecord.count
    error = invalid(:unresolved_ref, 1, change["operation"], includes: ["missing"]) do
      make.call("id" => "studio.invalid", "steps" => [create, unresolved]).save!
    end
    assert(error.errors.any? { |item| item[:kind] == :invalid_binding && item[:detail].include?("missing_input") },
      "Validator did not collect both errors")
    assert(Studio::OperationRecord.count == fail_count, "Validation failure persisted a record")
    invalid(:unresolved_ref, 0, change["operation"]) { make.call("steps" => [change, create]).to_recipe }
    invalid(:invalid_binding, 1, create["operation"]) { make.call("steps" => [create, create]).to_recipe }
    invalid(:type_mismatch, 1, "photocraft:select.lasso", includes: %w[layer_id polygon]) do
      make.call("steps" => [create, {"operation" => "photocraft:select.lasso",
        "params" => {"points" => {"$ref" => "base_layer"}}}]).to_recipe
    end
    invalid(:type_mismatch, 1, "photocraft:select.lasso", includes: %w[string polygon]) do
      make.call("steps" => [create, {"operation" => "photocraft:select.lasso",
        "params" => {"points" => {"$param" => "layerName"}}}]).to_recipe
    end
    invalid(:type_mismatch, 1, "photocraft:select.lasso", includes: %w[layer_id number]) do
      make.call("steps" => [create, {"operation" => "photocraft:select.lasso",
        "params" => {"feather" => {"$ref" => "base_layer"}}}]).to_recipe
    end

    foreign = YAML.safe_load_file(File.join(built_ins, "add_facial_hair.yml")).merge("id" => "studio.foreign")
    Studio::OperationRecord.create!(site: other_site, operation_id: "studio.foreign", surface: "image", version: 2,
      published: true, body: foreign)
    invalid(:unknown_operation, 1, "studio.foreign") do
      make.call("steps" => [create, {"operation" => "studio.foreign"}]).to_recipe
    end

    modified = YAML.safe_load(original_photo)
    modified["photocraft:layer.new.layer"]["returns"]["layer"] = "any"
    File.write(photo_file, YAML.dump(modified))
    begin
      Studio::OperationCatalog.for_site(site, **options)
      raise "Wildcard return was accepted"
    rescue ArgumentError => error
      assert(error.message.include?('Invalid returned handle type "any"'), error.message)
    end

    modified = YAML.safe_load(original_photo)
    modified["photocraft:layer.setProps"]["accepts"]["layer"] = "any"
    File.write(photo_file, YAML.dump(modified))
    make.call.to_recipe
    modified["photocraft:layer.setProps"]["accepts"].delete("layer")
    File.write(photo_file, YAML.dump(modified))
    drift_output = File.join(directory, "drift.pcraft")
    invalid(:type_mismatch, 1, change["operation"], includes: ["layer_id"]) do
      compiled.run!(executable: "/missing/cli", input: character, output: drift_output)
    end
    invalid(:type_mismatch, 1, change["operation"]) do
      entry.run!(input: character, output: drift_output)
    end
    assert(!File.exist?(drift_output), "Drift published an output")
    File.write(photo_file, original_photo)

    definitions = YAML.safe_load(original_photo)
    definitions["photocraft:layer.new.layer"]["returns"]["invented"] = "layer_id"
    File.write(photo_file, YAML.dump(definitions))
    begin
      Studio::OperationCatalog.for_site(site, **options)
      raise "Invented engine result was accepted"
    rescue ArgumentError => error
      assert(error.message.include?("Unknown returned handle: invented"), error.message)
    end
    definitions = YAML.safe_load(original_photo)
    definitions["photocraft:layer.select"]["accepts"]["invented"] = "layer_id"
    File.write(photo_file, YAML.dump(definitions))
    begin
      Studio::OperationCatalog.for_site(site, **options)
      raise "Invented accepting parameter was accepted"
    rescue ArgumentError => error
      assert(error.message.include?("Unknown accepting parameter: invented"), error.message)
    end
    File.write(photo_file, original_photo)

    thick = {"operation" => "studio.add_facial_hair", "params" => {"position" => {"$input" => "offset"}},
      "returns" => {"beard" => "hair_layer"}}
    thick_change = change.merge("params" => {"layer" => {"$ref" => "beard"}, "opacity" => 0.5})
    chain = make.call("id" => "studio.thick_combo", "steps" => [thick, thick_change],
      "inputs" => {"offset" => {"type" => "point", "default" => [2, 4], "min" => -10, "max" => 10}})
    chain_body = chain.save!(published: true).body.fetch("recipe")
    transform = chain_body.fetch("steps").find { |step| step["command"] == "edit.transform" }
    assert(transform.dig("params", "dx") == {"$input" => ["offset", 0]}, "Thick point projection did not compile")
    chain.to_recipe.run!(executable: photo, input: character, output: File.join(directory, "thick-input.pcraft"),
      inputs: {"offset" => [3, 5]})
    nested = make.call("id" => "studio.nested_combo",
      "steps" => [{"operation" => "studio.thick_combo", "returns" => {"new_beard" => "beard"}},
        thick_change.merge("params" => {"layer" => {"$ref" => "new_beard"}, "opacity" => 0.4})])
    nested.save!
    nested.to_recipe.run!(executable: photo, input: character, output: File.join(directory, "nested.pcraft"))

    builtin_options = options.merge(command_schema_directory: metadata)
    entries = Studio::OperationCatalog.for_site(DymondSite::Site.create!, **builtin_options)
    explicit = entries.count { |op| !op.accepts.empty? }
    puts "PASS save/load, typed binds, aggregate errors, thin/thick chains, nested execution and drift protection"
    puts "CATALOG: #{entries.length} operations, #{explicit} with explicit accepts, #{entries.length - explicit} without"
  end
ensure
  connection.schema_search_path = "public"
  connection.execute("DROP SCHEMA #{schema} CASCADE")
end
