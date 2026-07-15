# frozen_string_literal: true

class CreateMarlonProjectTypes < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_project_types do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_project_types, :key, unique: true
  end
end
