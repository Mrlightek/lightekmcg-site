class FundStudioAdPlacements < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_ad_payments do |t|
      t.references :placement, null: false, index: { unique: true }, foreign_key: { to_table: :studio_ad_placements }
      t.string :public_key, null: false
      t.integer :amount_cents, null: false
      t.string :state, null: false, default: "unfunded"
      t.integer :checkout_attempt, null: false, default: 0
      t.integer :checkout_amount_cents
      t.string :checkout_reference
      t.datetime :checkout_requested_at
      t.string :intent_reference
      t.string :charge_reference
      t.datetime :authorized_until
      t.datetime :captured_at
      t.datetime :reconcile_after
      t.timestamps
      t.index :public_key, unique: true
      t.index :checkout_reference, unique: true
      t.index :intent_reference, unique: true
      t.index :charge_reference, unique: true
      t.index %i[state reconcile_after]
    end

    create_table :studio_ad_payouts do |t|
      t.references :payment, null: false, foreign_key: { to_table: :studio_ad_payments }
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.string :role, null: false
      t.integer :amount_cents, null: false
      t.string :destination
      t.datetime :requested_at
      t.string :transfer_reference
      t.string :reversal_reference
      t.timestamps
      t.index %i[payment_id role], unique: true
      t.index :transfer_reference, unique: true
    end
  end
end
