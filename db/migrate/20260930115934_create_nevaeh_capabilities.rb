# frozen_string_literal: true

class CreateNevaehCapabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_capabilities do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.string  :domain, null: false
      t.text    :description

      t.string  :intent_name, null: false
      t.string  :subject_type

      t.string  :handler, null: false
      t.string  :queue, null: false, default: "default"
      t.integer :priority, null: false, default: 5

      t.string  :gatekeeper_capability

      t.jsonb :intent_patterns, null: false, default: []
      t.jsonb :expected_outcome, null: false, default: {}
      t.jsonb :failure_policy, null: false, default: {}
      t.jsonb :realtime, null: false, default: {}
      t.jsonb :input_adapter, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.jsonb :knowledge_article_ids, null: false, default: []

      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :nevaeh_capabilities, :slug, unique: true
    add_index :nevaeh_capabilities, :domain
    add_index :nevaeh_capabilities, :intent_name
    add_index :nevaeh_capabilities, :handler
    add_index :nevaeh_capabilities, :enabled
  end
end
