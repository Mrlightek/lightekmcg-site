require_relative "../support/studio_recipe_fixture"
require "active_record"
require "logger"
require "stringio"
require "securerandom"
require "tmpdir"
require_relative "../../app/services/studio/operation_catalog"

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

def reject(message)
  yield
  raise "Expected #{message}"
rescue ArgumentError => error
  assert(error.message.include?(message), error.message)
end

class RegistryProbe
  attr_reader :calls, :executable
  attr_accessor :online

  def initialize(adapter)
    @adapter = adapter
    @executable = adapter.executable
    @calls = 0
    @online = true
  end

  def runnable? = online && @adapter.runnable?

  def available_commands
    @calls += 1
    @adapter.available_commands
  end
end

root = File.expand_path("../..", __dir__)
directory = File.join(root, "config/studio/operations")
engines = Studio::Operation::Thin::SURFACES.keys.to_h do |engine|
  adapter = Studio::Operation::EngineAdapter.new(engine: engine, executable: ENV.fetch("#{engine.upcase}_CLI"))
  [engine, RegistryProbe.new(adapter)]
end
logs = StringIO.new
options = {engine_adapters: engines, built_in_directory: directory, logger: Logger.new(logs)}
catalog = Studio::OperationCatalog

ActiveRecord::Base.establish_connection(ENV.fetch("STUDIO_RECIPE_TEST_DATABASE_URL"))
connection = ActiveRecord::Base.connection
schema = "studio_operation_test_#{SecureRandom.hex(8)}"
connection.execute("CREATE SCHEMA #{schema}")
begin
  connection.schema_search_path = schema
  connection.create_table(:dymond_site_sites)
  ActiveRecord::Migration.verbose = false
  migration = CreateStudioOperationRecords.new
  migration.migrate(:up)
  site = DymondSite::Site.create!
  other_site = DymondSite::Site.create!

  entries = catalog.for_site(site, **options)
  thin = entries.select { |entry| entry.source == :thin }.to_h { |entry| [entry.id, entry] }
  thick = entries.select { |entry| entry.source == :thick }.to_h { |entry| [entry.id, entry] }
  assert(thick.keys.sort == %w[studio.add_facial_hair studio.animate_layer_position studio.set_layer_opacity], "Unexpected thick operations")
  thick.each do |id, operation|
    key = id.delete_prefix("studio.")
    recipe_path = File.join(root, "config/studio/recipes/#{key}.json")
    recipe = File.file?(recipe_path) ? Studio::Recipe.load(recipe_path) : operation.recipe
    body = JSON.parse(recipe.to_json)
    assert(JSON.parse(operation.recipe.to_json) == body, "#{id} recipe drifted")
    assert(operation.params_schema == body.fetch("parameters"), "#{id} exposes incorrect parameters")
    assert(operation.inputs_schema == body.fetch("inputs"), "#{id} exposes incorrect inputs")
    assert(operation.runnable?, "Expected #{id} to be runnable")
    recipe.command_ids.each do |command|
      entry = thin.fetch("#{recipe.engine}:#{command}")
      assert(entry.surface == operation.surface && entry.runnable?, "Wrong surface or offline #{entry.id}")
      assert(entry.params_signature.is_a?(String) && !entry.params_signature.empty?, "Missing signature #{entry.id}")
      assert(entry.params_schema, "Missing parameter schema #{entry.id}")
      assert(!entry.hidden, "Expected user-visible command #{entry.id}")
    end
  end
  assert(thin.fetch("photocraft:command.list").hidden, "Internal command was shown")
  assert(thin.fetch("effectcraft:layer.newSolid").display_name == "Layer · New Solid", "Command name was not humanized")
  lasso = thin.fetch("photocraft:select.lasso")
  assert(lasso.typed && lasso.params_schema.dig("properties", "points", "studio_type") == "polygon",
    "PhotoCraft lasso override did not expose a typed polygon")
  assert(lasso.typed_params.dig("points", "type") == "polygon" && lasso.requires == [:active_selection],
    "PhotoCraft authored type or requirement was lost")
  assert(!lasso.applicable?({}) && !lasso.applicable?(active_selection: false) &&
    lasso.applicable?(active_selection: true) && lasso.applicable?("active_selection" => true),
    "Lasso did not respect the active selection requirement")

  keys = thin.fetch("effectcraft:prop.addKey")
  command_schema = keys.params_schema
  assert(command_schema.is_a?(Hash) && command_schema.frozen?, "Expected immutable EffectCraft JSON Schema")
  assert(keys.typed && keys.requires == [:open_composition, :timeline_playhead] &&
    keys.applicable?(open_composition: true, timeline_playhead: true) &&
    !keys.applicable?(open_composition: true), "EffectCraft lost a requirement or did not enforce both flags")
  assert(command_schema.dig("properties", "time") ==
      {"description" => "time? (layer s by default)", "type" => "number", "unit" => "s"} &&
    command_schema.dig("properties", "layer", "description") == "layer?" &&
    command_schema["additionalProperties"] == false && command_schema["required"] == [],
    "Typed override did not merge with the native EffectCraft schema")

  untyped = thin.fetch("photocraft:edit.fill")
  assert(!untyped.typed && untyped.params_schema.is_a?(String) &&
    untyped.requires.empty? && untyped.applicable?({}), "Untyped PhotoCraft command was omitted or gated")
  assert(logs.string.include?("photocraft commands lack typed metadata"), "Missing untyped command log note")

  catalog.for_site(site, **options)
  assert(engines.values.all? { |engine| engine.calls == 1 }, "Registry did not read through cache")
  engines.fetch("photocraft").online = false
  offline = catalog.for_site(site, **options)
  stale = offline.find { |entry| entry.id == "photocraft:command.list" }
  assert(stale && stale.params_signature && !stale.runnable?, "Offline registry lost cached signatures")
  assert(offline.find { |entry| entry.id == "effectcraft:prop.addKey" }.runnable?, "An offline engine blocked the other engine")
  cold = engines.dup
  cold["photocraft"] = Studio::Operation::EngineAdapter.new(engine: "photocraft", executable: nil)
  offline = catalog.for_site(site, **options.merge(engine_adapters: cold))
  expected = offline.find { |entry| entry.id == "photocraft:layer.new.group" }
  assert(expected && !expected.runnable?, "Known command disappeared while offline")
  assert(!offline.find { |entry| entry.id == "studio.add_facial_hair" }.runnable?, "Thick operation with no CLI appeared runnable")
  broken = Class.new do
    def runnable? = true
    def available_commands = raise(IOError, "registry failed")
  end.new
  failed_discovery = catalog.for_site(site, **options.merge(engine_adapters: engines.merge("photocraft" => broken)))
  assert(!failed_discovery.find { |entry| entry.id == "photocraft:layer.new.group" }.runnable?,
    "Failed registry discovery appeared runnable")
  engines.fetch("photocraft").online = true

  Dir.mktmpdir("studio-command-override-") do |overrides|
    file = File.join(overrides, "photocraft.yml")
    checks = [
      ["bad_requirement", {"photocraft:select.lasso" => {"requires" => ["mask_exists"]}}, "Unknown or duplicate context requirement"],
      ["bad_type", {"photocraft:select.lasso" => {"typed_params" => {"points" => {"type" => "tuple"}}}}, "Malformed typed parameter"],
      ["bad_default", {"photocraft:select.lasso" => {"typed_params" => {"points" => {"type" => "polygon", "default" => [[0, 1]]}}}},
        "Invalid default for points"],
      ["bad_command", {"photocraft:select.missing" => {"requires" => []}}, "commands absent from registry"]
    ]
    checks.each do |_, override, expected_error|
      File.write(file, YAML.dump(override))
      reject(expected_error) { catalog.for_site(site, **options.merge(command_schema_directory: overrides)) }
    end
  end

  hair = catalog.find(site, "studio.add_facial_hair", **options)
  Dir.mktmpdir("studio-operation-") do |output|
    character = StudioRecipeFixture.path
    operation_png = File.join(output, "operation.png")
    recipe_png = File.join(output, "recipe.png")
    params = {"color" => "#433039", "position" => [3, 1], "scale" => 93}
    mask = hair.inputs_schema.fetch("mask_path").fetch("default").map { |x, y| [x + 2, y] }
    hair.run!(input: character, output: operation_png, parameters: params, inputs: {"mask_path" => mask})
    standalone = Studio::Recipe.load(File.join(root, "config/studio/recipes/add_facial_hair.json"))
    standalone.run!(executable: engines.fetch("photocraft").executable, input: character, output: recipe_png,
      parameters: params, inputs: {"mask_path" => mask})
    assert(File.binread(operation_png) == File.binread(recipe_png), "Thick operation differed from the direct recipe")

    source = YAML.safe_load_file(File.join(directory, "add_facial_hair.yml"))
    definition = source.fetch("recipe")
    parameters = definition.fetch("parameters")
    parameters["scaleX"] = parameters.delete("scale")
    transform = definition.fetch("steps").find { |step| step["command"] == "edit.transform" }
    transform.fetch("params").merge!("scaleX" => {"$param" => "scaleX"}, "scaleY" => 100)
    exposures = [{"parameter" => "scaleX", "as" => "Beard Width"}, {"parameter" => "density", "value" => 0.45},
      {"input" => "mask_path", "as" => "Guide Shape"}]
    operation = Studio::Operation::Thick.new(source.merge("exposes" => exposures, "accepts" => {"Guide Shape" => "polygon"}), engine_adapters: engines)
    assert(operation.params_schema.keys == ["Beard Width"] && operation.inputs_schema.keys == ["Guide Shape"],
      "Public schemas leaked fixed or internal names")
    renamed_png = File.join(output, "renamed.png")
    direct_png = File.join(output, "direct.png")
    defaults_png = File.join(output, "defaults.png")
    operation.run!(input: character, output: renamed_png, parameters: {"Beard Width" => 120}, inputs: {"Guide Shape" => mask})
    variants = Studio::Recipe.new(definition)
    variants.run!(executable: engines.fetch("photocraft").executable, input: character, output: direct_png,
      parameters: {"scaleX" => 120, "density" => 0.45}, inputs: {"mask_path" => mask})
    variants.run!(executable: engines.fetch("photocraft").executable, input: character, output: defaults_png,
      parameters: {"scaleX" => 120}, inputs: {"mask_path" => mask})
    assert(File.binread(renamed_png) == File.binread(direct_png), "Rename or fixed value changed the intended output")
    assert(File.binread(renamed_png) != File.binread(defaults_png), "Fixed density did not override the recipe default")
    reject("Unexposed parameters: density") { operation.run!(output: "unused", parameters: {"density" => 0.5}) }
    reject("Unexposed parameters: scaleX") { operation.run!(output: "unused", parameters: {"scaleX" => 120}) }

    invalid_exposures = [
      [[{"parameter" => "scaleX"}, {"parameter" => "scaleX"}], "Duplicate exposed parameter: scaleX"],
      [[{"parameter" => "scaleX", "as" => "density"}, {"parameter" => "density"}], "Duplicate public expose name: density"],
      [[{"parameter" => "scaleX", "as" => "Width"}, {"parameter" => "scaleX", "value" => 120}],
        "Duplicate exposed parameter: scaleX"],
      [[{"parameter" => "density", "value" => 1.5}], "Invalid parameter: density"]
    ]
    invalid_exposures.each do |entries, expected_error|
      reject(expected_error) { Studio::Operation::Thick.new(source.merge("exposes" => entries)) }
    end
  end

  source = YAML.safe_load_file(File.join(directory, "add_facial_hair.yml"))
  recorded = Studio::OperationRecord.create!(site: site, operation_id: source.fetch("id"), surface: "image",
    version: 2, published: true, body: source.merge("display_name" => "Tenant Facial Hair", "accepts" => {},
      "exposes" => [{"parameter" => "color"}]))
  Studio::OperationRecord.create!(site: site, operation_id: source.fetch("id"), surface: "image", version: 3,
    body: recorded.body.merge("recipe" => recorded.body.fetch("recipe").merge("version" => 3)))
  menu_hair = catalog.for_site(site, **options).select { |entry| entry.id == source.fetch("id") }
  assert(menu_hair.map(&:origin) == [:tenant] && menu_hair.first.recipe.version == 2,
    "Published tenant operation did not override built-in")
  assert(catalog.find(site, source.fetch("id"), origin: :builtin, **options).origin == :builtin,
    "Shadowed built-in is missing from explicit lookup")
  assert(catalog.find(site, source.fetch("id"), origin: :tenant, **options).display_name == "Tenant Facial Hair",
    "Tenant version is missing from explicit lookup")
  assert(catalog.find(other_site, source.fetch("id"), **options).origin == :builtin, "Tenant operation crossed sites")
  override = menu_hair.first
  assert(override.params_schema.keys == ["color"] && override.inputs_schema.empty?, "Hidden controls leaked")
  reject("Unexposed parameters: scale") { override.run!(output: "unused", parameters: {"scale" => 50}) }

  motion_file = File.join(directory, "animate_layer_position.yml")
  motion = YAML.safe_load_file(motion_file)
  alternate = motion.merge("id" => "studio.local_motion")
  Studio::OperationRecord.create!(site: site, operation_id: alternate.fetch("id"), surface: "motion",
    version: 2, published: true, body: alternate)
  menu = catalog.for_site(site, **options)
  assert(menu.any? { |entry| entry.id == alternate.fetch("id") } && menu.none? { |entry| entry.id == motion.fetch("id") },
    "Display name and surface override failed")
  assert(catalog.find(site, motion.fetch("id"), **options).origin == :builtin, "Name override lost built-in ID")

  reject("Unknown exposed parameter") do
    Studio::Operation::Thick.new(source.merge("exposes" => [{"parameter" => "missing"}]))
  end
  invalid = JSON.parse(JSON.generate(source))
  invalid.fetch("recipe").fetch("inputs").fetch("mask_path").delete("default")
  reject("Required inputs must be exposed") do
    Studio::Operation::Thick.new(invalid.merge("exposes" => []))
  end
  invalid.fetch("recipe").fetch("steps").first.delete("command")
  reject("Each recipe step needs a command ID") { Studio::Operation::Thick.new(invalid) }
  site.destroy!
  assert(!Studio::OperationRecord.exists?(site_id: site.id), "Tenant deletion did not cascade")
  migration.migrate(:down)
  assert(!connection.table_exists?(:studio_operation_records), "Operation migration did not roll back")
  counts = thin.values.group_by(&:engine).transform_values(&:size)
  puts "PASS registry discovery (#{counts}), caching, offline fallback, expose validation, tenant precedence and isolation"
  puts "PASS typed metadata merge, applicability checks, untyped logging and invalid metadata rejection"
  puts "PASS Add Facial Hair, renamed controls and fixed values match direct PhotoCraft recipes byte for byte"
ensure
  connection.schema_search_path = "public"
  connection.execute("DROP SCHEMA #{schema} CASCADE")
end
