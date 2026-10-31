# frozen_string_literal: true
class PersistLightekStudioWorkspaces < ActiveRecord::Migration[8.0]
  def up
    add_column :studio_projects, :owner_id, :bigint unless column_exists?(:studio_projects, :owner_id)
    add_column :studio_projects, :site_id, :bigint unless column_exists?(:studio_projects, :site_id)
    add_index :studio_projects, :owner_id unless index_exists?(:studio_projects, :owner_id)
    add_index :studio_projects, :site_id unless index_exists?(:studio_projects, :site_id)
    add_foreign_key :studio_projects, :users, column: :owner_id unless foreign_key_exists?(:studio_projects, :users, column: :owner_id)
    add_foreign_key :studio_projects, :dymond_site_sites, column: :site_id unless foreign_key_exists?(:studio_projects, :dymond_site_sites, column: :site_id)
    add_column :studio_projects, :is_template, :boolean, default: false, null: false unless column_exists?(:studio_projects, :is_template)
    add_column :studio_projects, :request_key, :string unless column_exists?(:studio_projects, :request_key)
    add_index :studio_projects, %i[owner_id request_key], unique: true unless index_exists?(:studio_projects, %i[owner_id request_key])
    add_column :studio_scenes, :lock_version, :integer, default: 0, null: false unless column_exists?(:studio_scenes, :lock_version)
    add_column :studio_publications, :request_key, :string unless column_exists?(:studio_publications, :request_key)
    unless index_exists?(:studio_publications, %i[studio_project_id request_key], name: "idx_studio_publication_request_unique")
      add_index :studio_publications, %i[studio_project_id request_key], unique: true, name: "idx_studio_publication_request_unique"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Reconciliation preserves schema that may have existed under version 20261031130000"
  end
end
