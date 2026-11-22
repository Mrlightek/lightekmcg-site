class AddNetworkOfficeAndExecutiveDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_network_office_files do |t|
      t.references :channel, null: false, foreign_key: {to_table: :lightek_team_network_channels}
      t.references :editor_peer, null: false, foreign_key: {to_table: :lightek_reservation_peers}
      t.string :key, null: false
      t.string :editor_name, null: false
      t.string :kind, null: false
      t.string :title, null: false
      t.text :content, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.index %i[channel_id key], unique: true
    end
    create_table :nevaeh_travel_bookings do |t|
      t.references :executive_case, null: false, foreign_key: {to_table: :nevaeh_executive_cases}
      t.string :kind, null: false
      t.string :source_id, null: false
      t.string :status, default: 'quoted', null: false
      t.string :amount, null: false
      t.string :currency, null: false
      t.json :quote, default: {}, null: false
      t.string :supplier_id
      t.string :reference
      t.timestamps
      t.index %i[executive_case_id kind source_id], unique: true
    end
    create_table :nevaeh_dcp_deliveries do |t|
      t.references :executive_case, null: false, foreign_key: {to_table: :nevaeh_executive_cases}
      t.references :recipient, null: false, foreign_key: {to_table: :users}
      t.string :key, null: false
      t.string :status, default: 'pending', null: false
      t.string :sha256
      t.string :rights_reference, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.string :error
      t.datetime :received_at
      t.timestamps
      t.index :key, unique: true
    end
  end
end
