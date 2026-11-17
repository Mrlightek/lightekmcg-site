class CreatePwaYoutubeUploads < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_pwa_youtube_uploads do |t|
      t.references :site, null: false
      t.references :user, null: false, foreign_key: true
      t.references :post, foreign_key: {on_delete: :nullify}, index: {unique: true}
      t.references :peer, foreign_key: {to_table: :lightek_reservation_peers}
      t.string :public_key, null: false, index: {unique: true}
      t.bigint :source_post_id
      t.bigint :source_blob_id
      t.string :source_grant, limit: 4096
      t.string :central_key
      t.string :status, null: false, default: 'queued'
      t.string :title, null: false
      t.text :description
      t.boolean :made_for_kids, null: false
      t.integer :byte_size, null: false
      t.string :checksum, null: false
      t.string :content_type, null: false
      t.string :video_id
      t.string :error_code
      t.datetime :session_started_at
      t.datetime :withdraw_requested_at
      t.datetime :consented_at, null: false
      t.timestamps
    end
    add_index :lightek_pwa_youtube_uploads, [:peer_id, :source_post_id], unique: true, name: 'pwa_peer_youtube_source'
  end
end
