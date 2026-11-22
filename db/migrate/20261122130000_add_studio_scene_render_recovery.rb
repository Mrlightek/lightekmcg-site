class AddStudioSceneRenderRecovery < ActiveRecord::Migration[8.0]
  def change
    add_column :studio_scene_renders, :request_id, :string
    add_column :studio_scene_renders, :scene_revision, :integer
    add_column :studio_scene_renders, :retry_of_id, :bigint
    add_column :studio_scene_renders, :claim_token, :string
    add_column :studio_scene_renders, :lease_expires_at, :datetime
    add_column :studio_scene_renders, :failed_phase, :string

    add_index :studio_scene_renders, [:studio_scene_id, :request_id], unique: true,
      name: "index_studio_scene_renders_on_scene_and_request"
    add_index :studio_scene_renders, [:status, :created_at]
    add_index :studio_scene_renders, [:status, :lease_expires_at]
  end
end
