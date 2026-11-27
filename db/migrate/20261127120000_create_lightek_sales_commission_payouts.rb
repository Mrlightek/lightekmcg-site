# frozen_string_literal: true

class CreateLightekSalesCommissionPayouts < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_sales_partners, :payout_email, :string
    add_column :lightek_sales_partners, :payout_recipient_ref, :string
    add_column :lightek_sales_partners, :payout_sender_ref, :string
    add_column :lightek_sales_partners, :payout_live, :boolean

    create_table :lightek_sales_commission_payouts do |t|
      t.references :referral, null: false, index: {unique: true}, foreign_key: {to_table: :lightek_sales_referrals}
      t.references :order, null: false, index: {unique: true}, foreign_key: {to_table: :lightek_commerce_orders}
      t.references :owner, null: false, foreign_key: {to_table: :users}
      t.references :released_by, foreign_key: {to_table: :users}
      t.bigint :amount_cents, null: false
      t.string :sender_ref, null: false
      t.string :recipient_ref, null: false
      t.boolean :live, null: false
      t.string :provider_ref
      t.string :state, null: false, default: 'preparing'
      t.bigint :review_debit_cents
      t.string :review_digest
      t.datetime :release_attempted_at
      t.timestamps
      t.index :provider_ref, unique: true
      t.check_constraint 'amount_cents > 0', name: 'sales_commission_payout_positive'
    end
  end
end
