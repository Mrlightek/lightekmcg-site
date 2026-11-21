class CreateStudioAdNetworks < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_ad_networks do |t|
      t.references :site, null: false, foreign_key: { to_table: :dymond_site_sites }
      t.string :name, null: false
      t.timestamps
    end

    create_table :studio_ad_memberships do |t|
      t.references :network, null: false, foreign_key: { to_table: :studio_ad_networks }
      t.references :station_site, null: false, foreign_key: { to_table: :dymond_site_sites }
      t.timestamps
      t.index %i[station_site_id network_id], unique: true
    end

    create_table :studio_ad_campaigns do |t|
      t.references :network, null: false, foreign_key: { to_table: :studio_ad_networks }
      # Removing a Studio asset keeps booked and delivered ad records intact.
      t.references :asset, null: false
      t.bigint :blob_id, null: false
      t.string :name, null: false
      t.integer :seconds, null: false
      t.integer :rate_cents, null: false
      t.integer :network_bps, null: false
      t.integer :producer_bps, null: false
      t.integer :platform_bps, null: false
      t.boolean :open_for_booking, null: false, default: false
      t.timestamps
    end

    create_table :studio_ad_placements do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :studio_ad_campaigns }
      t.references :station_site, null: false, foreign_key: { to_table: :dymond_site_sites }
      # As-aired receipts survive removal of the channel and its rundown.
      t.bigint :airing_id, null: false
      t.integer :row_index, null: false
      t.bigint :producer_id
      t.integer :station_cents, null: false
      t.integer :producer_cents, null: false
      t.integer :network_cents, null: false
      t.integer :platform_cents, null: false
      t.datetime :delivered_at
      t.timestamps
      t.index %i[airing_id row_index], unique: true
    end
  end
end
