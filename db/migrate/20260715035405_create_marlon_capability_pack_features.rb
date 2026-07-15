# frozen_string_literal: true

class CreateMarlonCapabilityPackFeatures < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_capability_pack_features do |t|
      t.references :capability_pack, null: false, foreign_key: { to_table: :marlon_capability_packs }, index: false
      t.references :feature, null: false, foreign_key: { to_table: :marlon_features }, index: false
      t.integer :position, null: false, default: 0
      t.json :configuration, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_capability_pack_features,
      [:capability_pack_id, :feature_id], unique: true,
      name: "idx_marlon_pack_features_unique"
  end
end
