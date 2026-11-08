class AddReservationFederation < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_reservation_peers do |t|
      t.string :key, null: false
      t.string :token_digest, null: false
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}, index: {unique: true}
      t.references :merchant, null: false, foreign_key: {to_table: :users}
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}, index: {unique: true}
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :lightek_reservation_peers, :key, unique: true
    create_table :lightek_reservation_intents do |t|
      t.references :peer, null: false, foreign_key: {to_table: :lightek_reservation_peers}
      t.references :resource, null: false, foreign_key: {to_table: :lightek_reservation_resources}
      t.references :reservation, foreign_key: {to_table: :lightek_reservations}
      t.references :customer, foreign_key: {to_table: :users}
      t.string :token, null: false
      t.string :checkout_key, null: false
      t.string :remote_subject, null: false
      t.datetime :starts_at, null: false
      t.datetime :expires_at, null: false
      t.integer :price_cents, null: false
      t.timestamps
    end
    add_index :lightek_reservation_intents, :token, unique: true
    add_index :lightek_reservation_intents, [:peer_id, :checkout_key], unique: true, name: 'idx_reservation_peer_checkout'
  end
end
