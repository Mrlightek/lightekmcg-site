class ExchangeStudioAdCampaigns < ActiveRecord::Migration[8.0]
  def change
    add_column :studio_ad_networks, :exchange_key, :string
    add_column :studio_ad_networks, :imported, :boolean, default: false, null: false
    add_reference :studio_ad_networks, :peer, foreign_key: { to_table: :lightek_reservation_peers }
    add_index :studio_ad_networks, %i[site_id exchange_key], unique: true

    add_column :studio_ad_campaigns, :exchange_key, :string
    add_column :studio_ad_campaigns, :creative_sha256, :string
    add_column :studio_ad_campaigns, :exchange_authority, :boolean, default: true, null: false
    add_index :studio_ad_campaigns, %i[network_id exchange_key], unique: true
    add_index :studio_ad_campaigns, :exchange_key, unique: true, where: "exchange_authority"

    change_column_null :studio_ad_placements, :airing_id, true
    add_reference :studio_ad_placements, :peer, foreign_key: { to_table: :lightek_reservation_peers }
    add_column :studio_ad_placements, :exchange_key, :string
    add_column :studio_ad_placements, :scheduled_start, :datetime
    add_column :studio_ad_placements, :scheduled_end, :datetime
    add_column :studio_ad_placements, :remote_retired, :boolean, default: false, null: false
    add_column :studio_ad_placements, :remote_authorized_until, :datetime
    add_column :studio_ad_placements, :remote_state, :string
    add_column :studio_ad_placements, :sync_after, :datetime
    add_index :studio_ad_placements, :exchange_key, unique: true
    add_index :studio_ad_placements, :sync_after
  end
end
