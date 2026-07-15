# frozen_string_literal: true

class CreateMarlonCapabilityPacks < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_capability_packs do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_capability_packs, :key, unique: true
  end
end
