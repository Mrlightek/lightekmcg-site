# frozen_string_literal: true
class CreateNevaehOperatingSystem < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_os_actions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :request_key, null: false
      t.jsonb :command, null: false, default: {}
      t.string :status, null: false, default: 'pending'
      t.jsonb :result, null: false, default: {}
      t.text :error
      t.timestamps
    end
    create_table :nevaeh_os_memories do |t|
      t.references :user, null: false, foreign_key: true
      t.string :category, null: false
      t.text :text, null: false
      t.timestamps
    end
    create_table :nevaeh_os_consents do |t|
      t.references :user, null: false, foreign_key: true
      t.string :category, null: false
      t.boolean :enabled, null: false, default: false
      t.timestamps
    end
    create_table :nevaeh_os_sources do |t|
      t.references :user, null: false, foreign_key: true
      t.string :url, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.string :sha256, null: false
      t.string :status, null: false, default: 'draft' 
      t.timestamps
    end
    create_table :nevaeh_os_agents do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :role, null: false, default: 'Assistant'
      t.text :instructions
      t.date :birth_date
      t.string :birth_time
      t.string :birth_place
      t.timestamps
    end
    add_index :nevaeh_os_actions, [:user_id, :request_key], unique: true
    add_index :nevaeh_os_consents, [:user_id, :category], unique: true
  end
end
