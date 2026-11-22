class AddStudioSceneAnimation < ActiveRecord::Migration[8.0]
  def change
    add_column :studio_assets, :animation_role, :string
    add_column :studio_assets, :dimension_mode, :string
    add_column :studio_projects, :animation_workspace, :boolean, null: false, default: false
    add_column :studio_scenes, :scene_spec, :jsonb

    create_table :studio_scene_renders do |t|
      t.references :studio_scene, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.integer :progress, null: false, default: 0
      t.jsonb :manifest, null: false
      t.string :error_message
      t.timestamps
    end
  end
end
