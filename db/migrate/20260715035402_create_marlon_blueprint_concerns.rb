# frozen_string_literal: true

class CreateMarlonBlueprintConcerns < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_blueprint_concerns do |t|
      t.references :feature, null: false, foreign_key: { to_table: :marlon_features }
      t.string :key, null: false
      t.string :name, null: false
      t.string :target_type, null: false, default: "model"
      t.string :implementation_class
      t.text :description
      t.boolean :active, null: false, default: true
      t.json :configuration, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_blueprint_concerns, [:feature_id, :key], unique: true,
      name: "idx_marlon_concerns_feature_key"
  end
end
