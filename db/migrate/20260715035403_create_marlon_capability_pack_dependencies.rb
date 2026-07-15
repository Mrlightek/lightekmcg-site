# frozen_string_literal: true

class CreateMarlonCapabilityPackDependencies < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_capability_pack_dependencies do |t|
      t.references :capability_pack, null: false, foreign_key: { to_table: :marlon_capability_packs }, index: false
      t.references :dependency, null: false, foreign_key: { to_table: :marlon_capability_packs }, index: false
      t.timestamps
    end

    add_index :marlon_capability_pack_dependencies,
      [:capability_pack_id, :dependency_id], unique: true,
      name: "idx_marlon_pack_dependencies_unique"
  end
end
