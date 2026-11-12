class ConnectFederatedCommerceSettlement < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_orders, :network_reference, :string
    add_column :lightek_commerce_orders, :network_invoice_reference, :string
    add_index :lightek_commerce_orders, [:network_reference, :network_invoice_reference], unique: true, name: "idx_commerce_network_receipt"
    create_table :lightek_commerce_network_accounts do |t|
      t.references :peer, null: false, foreign_key: {to_table: :lightek_reservation_peers}
      t.references :user, null: false, foreign_key: true
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.string :source_subject, null: false
      t.timestamps
    end
    add_index :lightek_commerce_network_accounts, [:peer_id, :source_subject], unique: true, name: "idx_commerce_network_account"
    create_table :lightek_commerce_network_sales do |t|
      t.references :peer, null: false, foreign_key: {to_table: :lightek_reservation_peers}
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}, index: {unique: true}
      t.references :source_shipping_quote, foreign_key: {to_table: :lightek_shipping_quotes}, index: {unique: true, name: "idx_network_shipping_source"}
      t.string :public_key, null: false, index: {unique: true}
      t.string :source_key, null: false
      t.jsonb :source_snapshot, default: {}, null: false
      t.string :return_url, null: false
      t.timestamps
    end
    add_index :lightek_commerce_network_sales, [:peer_id, :source_key], unique: true, name: "idx_commerce_network_sale"
  end
end
