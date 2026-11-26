module Studio
  class RecipeRecord < ApplicationRecord
    self.table_name = "studio_recipes"

    belongs_to :site, class_name: "DymondSite::Site", optional: false

    normalizes :name, with: ->(name) { name.strip }
    validates :name, presence: true, length: {maximum: 120}
    validates :version, numericality: {only_integer: true, greater_than: 0},
      uniqueness: {scope: [:site_id, :name]}
    validates :source_tutorial_reference, length: {maximum: 2048}
    validates :published, inclusion: {in: [true, false]}
    validate :valid_recipe_body

    scope :published, -> { where(published: true) }

    def recipe
      Recipe.new(body)
    end

    private

    def valid_recipe_body
      parsed_recipe = recipe
      if parsed_recipe.name != name || parsed_recipe.version != version
        errors.add(:body, "must have the same name and version as the record")
      end
    rescue ArgumentError => error
      errors.add(:body, error.message)
    end
  end
end
