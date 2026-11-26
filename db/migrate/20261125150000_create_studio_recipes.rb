class CreateStudioRecipes < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_recipes do |t|
      t.references :site, null: false, index: false,
        foreign_key: {to_table: :dymond_site_sites, on_delete: :cascade}
      t.string :name, limit: 120, null: false
      t.integer :version, null: false
      t.jsonb :body, null: false
      t.text :source_tutorial_reference
      t.boolean :published, null: false, default: false
      t.timestamps
    end

    add_index :studio_recipes, [:site_id, :name, :version], unique: true
    add_check_constraint :studio_recipes, "version > 0", name: "studio_recipes_positive_version"
  end
end
