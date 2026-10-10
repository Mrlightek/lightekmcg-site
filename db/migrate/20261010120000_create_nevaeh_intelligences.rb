# frozen_string_literal: true

class CreateNevaehIntelligences < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_intelligences do |t|
      t.string :name, null: false
      t.string :intent_key, null: false
      t.string :model_name
      t.string :operation, null: false
      t.references :nevaeh_capability, null: false, foreign_key: true, index: true
      t.jsonb :instructions, null: false, default: {}
      t.string :status, null: false, default: 'draft'
      t.string :execution_mode, null: false, default: 'async'
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :nevaeh_intelligences, :intent_key, unique: true
    add_index :nevaeh_intelligences, :status
  end
end
