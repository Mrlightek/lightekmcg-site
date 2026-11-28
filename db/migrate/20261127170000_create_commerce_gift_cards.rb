# frozen_string_literal: true

class CreateCommerceGiftCards < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_commerce_gift_cards do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :purchase_order, null: false, index: {unique: true}, foreign_key: {to_table: :lightek_commerce_orders}
      t.string :store_scope, null: false
      t.boolean :livemode, null: false
      t.string :code_digest, null: false
      t.text :encrypted_code, null: false
      t.integer :face_cents, null: false
      t.integer :available_cents, null: false
      t.datetime :blocked_at
      t.datetime :disputed_at
      t.datetime :revoked_at
      t.timestamps
      t.index :code_digest, unique: true
      t.check_constraint 'available_cents >= 0 AND available_cents <= face_cents AND face_cents > 0',
        name: 'commerce_gift_card_balance'
    end

    create_table :lightek_commerce_gift_redemptions do |t|
      t.references :order, null: false, index: {unique: true}, foreign_key: {to_table: :lightek_commerce_orders}
      t.references :gift_card, null: false, foreign_key: {to_table: :lightek_commerce_gift_cards}
      t.integer :amount_cents, null: false
      t.integer :cash_cents, null: false
      t.string :state, null: false, default: 'held'
      t.string :tax_calculation, null: false
      t.string :tax_transaction
      t.string :tax_reversal
      t.datetime :payment_attempted_at
      t.timestamps
      t.check_constraint 'amount_cents > 0 AND cash_cents >= 0', name: 'commerce_gift_redemption_amount'
      t.check_constraint "state IN ('held', 'captured', 'released', 'refunded')", name: 'commerce_gift_redemption_state'
    end

    add_column :lightek_commerce_orders, :gift_store_scope, :string
    add_column :lightek_commerce_orders, :gift_applied_cents, :integer, null: false, default: 0
    add_column :lightek_commerce_refunds, :gift_restore_cents, :integer, null: false, default: 0
  end
end
