# frozen_string_literal: true
class PersistLightekStudioWorkspaces < ActiveRecord::Migration[8.0]
  def change
    add_reference :studio_projects, :owner, foreign_key: { to_table: :users }
    add_reference :studio_projects, :site, foreign_key: { to_table: :dymond_site_sites }
    add_column :studio_projects, :is_template, :boolean, default: false, null: false
    add_column :studio_projects, :request_key, :string
    add_index :studio_projects, %i[owner_id request_key], unique: true
    add_column :studio_scenes, :lock_version, :integer, default: 0, null: false
    add_column :studio_publications, :request_key, :string
    add_index :studio_publications, %i[studio_project_id request_key], unique: true, name: "idx_studio_publication_request_unique"
  end
end
