# frozen_string_literal: true

class CreateMarlonProjectTypeCapabilityPacks < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_project_type_capability_packs do |t|
      t.references :project_type, null: false, foreign_key: { to_table: :marlon_project_types }, index: false
      t.references :capability_pack, null: false, foreign_key: { to_table: :marlon_capability_packs }, index: false
      t.integer :position, null: false, default: 0
      t.json :configuration, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_project_type_capability_packs,
      [:project_type_id, :capability_pack_id], unique: true,
      name: "idx_marlon_project_type_packs_unique"
  end
end
