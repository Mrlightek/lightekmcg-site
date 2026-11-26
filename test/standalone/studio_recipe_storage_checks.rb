require "active_record"
require "securerandom"
require_relative "../../app/services/studio/recipe"
require_relative "../../app/services/studio/recipe_catalog"

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

module DymondSite
  class Site < ApplicationRecord
    self.table_name = "dymond_site_sites"
  end
end

require_relative "../../app/models/studio/recipe_record"
require_relative "../../db/migrate/20261125150000_create_studio_recipes"

def assert(condition, message)
  raise message unless condition
end

ActiveRecord::Base.establish_connection(ENV.fetch("STUDIO_RECIPE_TEST_DATABASE_URL"))
connection = ActiveRecord::Base.connection
schema = "studio_recipe_test_#{SecureRandom.hex(8)}"
connection.execute("CREATE SCHEMA #{schema}")
begin
  connection.schema_search_path = schema
  connection.create_table(:dymond_site_sites)
  ActiveRecord::Migration.verbose = false
  migration = CreateStudioRecipes.new
  migration.migrate(:up)

  site = DymondSite::Site.create!
  other = DymondSite::Site.create!
  directory = File.expand_path("../../config/studio/recipes", __dir__)
  source = JSON.parse(File.read(File.join(directory, "add_facial_hair.json")))
  create = lambda do |owner, version, published|
    name = "Add Facial Hair"
    Studio::RecipeRecord.create!(site: owner, name: name, version: version,
      body: source.merge("name" => name, "version" => version), published: published,
      source_tutorial_reference: "tutorial/character-effects")
  end
  create.call(site, 1, true)
  current = create.call(site, 2, true)
  create.call(site, 3, false)
  foreign = create.call(other, 4, true)
  entries = Studio::RecipeCatalog.for_site(site, built_in_directory: directory)
  assert(entries.map(&:key) == ["builtin:add_facial_hair", "builtin:animate_layer_position", "tenant:#{current.id}"],
    "Expected built-ins and only the latest published version for the current site")
  assert(entries.last.recipe.version == 2 && entries.last.source_tutorial_reference == "tutorial/character-effects",
    "Menu lost the recipe version or tutorial reference")
  assert(Studio::RecipeCatalog.for_site(other, built_in_directory: directory).last.key == "tenant:#{foreign.id}",
    "Tenant menu scope is incorrect")

  duplicate = current.dup
  assert(!duplicate.valid? && duplicate.errors[:version].any?, "Accepted duplicate version")
  begin
    Studio::RecipeRecord.insert_all!([current.attributes.except("id")])
    raise "Database accepted duplicate version"
  rescue ActiveRecord::RecordNotUnique
    nil
  end
  draft = Studio::RecipeRecord.new(site: site, name: "Draft", version: 1,
    body: source.merge("name" => "Draft", "version" => 1))
  assert(draft.published == false, "Recipes should start unpublished")
  draft.body["steps"][1]["params"]["layer"] = {"$ref" => "missing"}
  assert(!draft.valid? && draft.errors[:body].any?, "Stored an unresolved binding")
  site.destroy!
  assert(!Studio::RecipeRecord.exists?(site_id: site.id), "Tenant delete did not cascade")
  assert(Studio::RecipeRecord.exists?(foreign.id), "Tenant delete crossed sites")
  migration.migrate(:down)
  assert(!connection.table_exists?(:studio_recipes), "Recipe migration did not roll back")
  puts "PASS PostgreSQL: migration up/down, isolation, menu version, publication, validation and cascade"
ensure
  connection.schema_search_path = "public"
  connection.execute("DROP SCHEMA #{schema} CASCADE")
end
