class CreateLightekLiveViewers < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_live_viewers do |t|
      t.references :studio_live_operation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :last_seen_at, null: false
    end
    add_index :lightek_live_viewers, [:studio_live_operation_id, :user_id], unique: true, name: 'idx_lightek_live_viewer_identity'
    add_index :lightek_live_viewers, :last_seen_at
  end
end
