class CreateStudioRemoteRenders < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_remote_renders do |t|
      t.references :peer, null: false, foreign_key: {to_table: :lightek_reservation_peers}
      t.references :studio_operation, null: false, foreign_key: true, index: {unique: true}
      t.string :request_key, :manifest_digest, null: false
      t.jsonb :result, null: false, default: {}
      t.datetime :enqueued_at
      t.timestamps
    end
    add_index :studio_remote_renders, [:peer_id, :request_key], unique: true
  end
end
