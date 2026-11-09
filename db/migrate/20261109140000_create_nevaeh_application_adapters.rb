# frozen_string_literal: true
class CreateNevaehApplicationAdapters < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_application_adapters do |t|
      t.references :user, null: false, foreign_key: true
      t.string :package, null: false
      t.string :name, null: false
      t.string :status, null: false, default: 'draft'
      t.jsonb :operations, null: false, default: {}
      t.jsonb :documentation, null: false, default: {}
      t.jsonb :verification, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :nevaeh_application_adapters, [:user_id,:package], unique: true, name: 'idx_nevaeh_app_adapter_owner'
  end
end
