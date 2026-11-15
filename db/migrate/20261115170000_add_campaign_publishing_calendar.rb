class AddCampaignPublishingCalendar < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_marketing_media_bindings do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :campaign, null: false, foreign_key: {to_table: :lightek_marketing_campaigns}
      t.references :artifact, foreign_key: {on_delete: :nullify}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.string :token, null: false, index: {unique: true}
      t.string :filename, :delivery_host, null: false
      t.jsonb :source_snapshot, null: false, default: {}
      t.datetime :revoked_at
      t.timestamps
    end
    add_reference :lightek_marketing_campaigns, :media_binding, foreign_key: {to_table: :lightek_marketing_media_bindings}
    create_table :lightek_marketing_publication_slots do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :campaign, null: false, foreign_key: {to_table: :lightek_marketing_campaigns}
      t.references :connection, null: false, foreign_key: {to_table: :lightek_marketing_social_connections}
      t.references :scheduled_by, null: false, foreign_key: {to_table: :users}
      t.references :social_post, foreign_key: {to_table: :lightek_marketing_social_posts}
      t.string :request_key, :content_digest, null: false
      t.string :status, null: false, default: 'scheduled'
      t.string :time_zone, null: false, default: 'UTC'
      t.datetime :scheduled_at, null: false
      t.datetime :queue_requested_at, :started_at, :finished_at
      t.text :error_message
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_marketing_publication_slots, [:site_id, :request_key], unique: true, name: 'idx_publication_slot_request'
    add_index :lightek_marketing_publication_slots, [:campaign_id, :connection_id], unique: true, where: "status != 'canceled'", name: 'idx_publication_slot_destination'
    add_index :lightek_marketing_publication_slots, [:status, :scheduled_at]
  end
end
