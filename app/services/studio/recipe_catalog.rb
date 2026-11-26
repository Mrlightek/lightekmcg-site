module Studio
  class RecipeCatalog
    Entry = Data.define(:key, :source, :recipe, :source_tutorial_reference)

    def self.for_site(site, built_in_directory: Rails.root.join("config/studio/recipes"))
      raise ArgumentError, "A persisted Studio site is required" unless site.is_a?(DymondSite::Site) && site.persisted?

      entries = Dir.glob(File.join(built_in_directory, "*.json")).sort.map do |path|
        recipe = Recipe.load(path)
        Entry.new(key: "builtin:#{File.basename(path, '.json')}", source: :builtin, recipe: recipe,
          source_tutorial_reference: nil)
      end

      current = RecipeRecord.published.where(site_id: site.id).order(name: :asc, version: :desc)
        .group_by(&:name).values.map(&:first)
      entries + current.map do |record|
        Entry.new(key: "tenant:#{record.id}", source: :tenant, recipe: record.recipe,
          source_tutorial_reference: record.source_tutorial_reference)
      end
    end
  end
end
