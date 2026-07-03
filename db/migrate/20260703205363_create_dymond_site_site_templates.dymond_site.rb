# frozen_string_literal: true
# This migration comes from dymond_site (originally 20260703204651)
class CreateDymondSiteSiteTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :dymond_site_site_templates do |t|
      t.string :name, null: false
      t.string :key,  null: false
      t.string :description
      t.jsonb  :settings, default: {}
      t.boolean :preset, default: false
      t.timestamps
    end
    add_index :dymond_site_site_templates, :key, unique: true
  end
end
