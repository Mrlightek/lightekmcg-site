class AddBroadcastNetworkDistributionAndMeasurement < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_network_carriages do |t|
      t.references :channel, null: false, index: { unique: true },
        foreign_key: { to_table: :studio_broadcast_channels, on_delete: :cascade }
      t.string :status, null: false, default: "requested"
      t.string :ownership
      t.timestamps
    end

    create_table :studio_program_licenses do |t|
      t.references :licensor_site, null: false, foreign_key: { to_table: :dymond_site_sites }
      t.references :licensee_site, null: false, foreign_key: { to_table: :dymond_site_sites }
      t.bigint :asset_id, null: false
      t.bigint :blob_id, null: false
      t.string :title, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :status, null: false, default: "offered"
      t.timestamps
      t.index %i[licensee_site_id status ends_at]
    end

    add_column :studio_channel_airings, :measurement, :jsonb, default: {}, null: false
    create_table :studio_broadcast_view_sessions do |t|
      # Snapshot IDs preserve aggregate reports when a channel or airing is removed.
      t.bigint :channel_id, null: false
      t.bigint :station_site_id, null: false
      t.bigint :outlet_site_id, null: false
      t.bigint :airing_id, null: false
      t.integer :ad_row, default: -1, null: false
      t.date :day, null: false
      t.string :platform, null: false
      t.string :session_key, null: false
      t.bigint :highest_sequence, null: false, default: -1
      t.bigint :sequence_window, null: false, default: 0
      t.integer :segments, null: false, default: 0
      t.bigint :media_ms, null: false, default: 0
      t.timestamps
      t.index %i[session_key channel_id airing_id ad_row day], unique: true, name: :index_studio_broadcast_session_context
      t.index %i[station_site_id day], name: :index_studio_broadcast_station_day
      t.index %i[outlet_site_id day], name: :index_studio_broadcast_outlet_day
    end
  end
end
