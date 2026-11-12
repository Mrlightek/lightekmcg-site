class AddNestedResellerSaleShares < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :upstream_share_bps, :integer, default: 0, null: false
    add_check_constraint :users, "upstream_share_bps BETWEEN 0 AND 10000", name: "account_upstream_share_valid"
    add_column :lightek_commerce_orders, :revenue_share_snapshot, :jsonb, default: [], null: false
    create_table :lightek_commerce_revenue_allocations do |t|
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}
      t.references :beneficiary, null: false, foreign_key: {to_table: :users}
      t.integer :basis_points, null: false
      t.integer :amount_cents, null: false
      t.integer :reversed_cents, default: 0, null: false
      t.string :currency, null: false, default: "usd"
      t.string :status, null: false, default: "pending"
      t.string :transfer_reference
      t.datetime :settled_at
      t.timestamps
    end
    add_index :lightek_commerce_revenue_allocations, [:order_id, :beneficiary_id], unique: true, name: "idx_revenue_order_beneficiary"
    add_check_constraint :lightek_commerce_revenue_allocations, "amount_cents >= 0 AND basis_points BETWEEN 0 AND 10000", name: "revenue_allocation_amount_valid"
  end
end
