class CreatePwaCreatorPayments < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_pwa_creator_offers do |t|
      t.references :site, null: false
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.integer :monthly_cents, null: false, default: 500
      t.boolean :enabled, null: false, default: false
      t.timestamps
    end
    add_index :lightek_pwa_creator_offers, [:site_id, :creator_id], unique: true, name: 'pwa_creator_offer_identity'
    create_table :lightek_pwa_creator_payments do |t|
      t.references :site, null: false
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.references :supporter, null: false, foreign_key: {to_table: :users}
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}, index: {unique: true}
      t.references :post, foreign_key: {on_delete: :nullify}
      t.string :kind, null: false
      t.string :request_key, null: false
      t.integer :principal_cents, null: false
      t.integer :fee_cents, null: false
      t.timestamps
    end
    add_index :lightek_pwa_creator_payments, [:site_id, :supporter_id, :request_key], unique: true, name: 'pwa_support_payment_identity'
    create_table :lightek_pwa_creator_earnings do |t|
      t.references :creator_payment, null: false, foreign_key: {to_table: :lightek_pwa_creator_payments}
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}, index: {unique: true}
      t.integer :principal_cents, null: false
      t.string :state, null: false, default: 'held'
      t.string :charge_reference
      t.string :transfer_reference
      t.string :reversal_reference
      t.string :destination_account
      t.datetime :available_at
      t.string :hold_reason
      t.timestamps
    end
    add_index :lightek_pwa_creator_earnings, :charge_reference
  end
end
