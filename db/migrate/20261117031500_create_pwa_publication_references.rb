class CreatePwaPublicationReferences < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_pwa_publication_references do |t|
      t.bigint :peer_id, null: false
      t.bigint :remote_post_id, null: false
      t.references :post, foreign_key: true
      t.bigint :revision, null: false, default: 0
      t.boolean :removed, null: false, default: false
      t.timestamps
    end
    add_index :lightek_pwa_publication_references, [:peer_id, :remote_post_id], unique: true, name: 'pwa_remote_post_unique'
    create_table :lightek_pwa_publication_outboxes do |t|
      t.bigint :site_id, null: false
      t.bigint :remote_post_id, null: false
      t.bigint :revision, null: false, default: 0
      t.bigint :delivered_revision, null: false, default: 0
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    add_index :lightek_pwa_publication_outboxes, [:site_id, :remote_post_id], unique: true, name: 'pwa_outbox_post_unique'
  end
end
