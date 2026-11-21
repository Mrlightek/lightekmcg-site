class ConnectBroadcastAdDemand < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_ad_demand_sources do |t|
      t.bigint :site_id, null: false
      t.string :name, null: false
      t.string :vault_slug, null: false
      t.string :platform, null: false, default: "both"
      t.integer :position, null: false, default: 0
      t.boolean :enabled, null: false, default: false
      t.timestamps
      t.index %i[site_id name], unique: true
    end
    create_table :studio_ad_provider_statements do |t|
      t.bigint :source_id, null: false
      t.string :reference, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.bigint :impressions, null: false
      t.bigint :reported_cents, null: false
      t.bigint :received_cents
      t.string :deposit_reference
      t.datetime :reconciled_at
      t.bigint :reconciled_by_id
      t.timestamps
      t.index %i[source_id reference], unique: true
    end
    create_table :studio_ad_stream_profiles do |t|
      t.bigint :site_id, null: false
      t.bigint :channel_id, null: false
      t.string :platform, null: false
      t.string :playback_url, null: false
      t.string :decision_key, null: false
      t.index :decision_key, unique: true
      t.timestamps
      t.index %i[site_id channel_id platform], unique: true, name: "idx_studio_ad_stream_profiles"
    end
    create_table :studio_ad_viewing_links do |t|
      t.bigint :site_id, null: false
      t.bigint :user_id, null: false
      t.string :code_digest, null: false, index: { unique: true }
      t.datetime :expires_at, null: false
      t.datetime :linked_at
      t.index %i[site_id user_id]
      t.timestamps
    end
    create_table :studio_ad_viewing_offers do |t|
      t.bigint :site_id, null: false, index: { unique: true }
      t.bigint :product_id, null: false
      t.timestamps
    end
  end
end
