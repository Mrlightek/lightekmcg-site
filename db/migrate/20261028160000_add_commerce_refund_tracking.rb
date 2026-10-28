class AddCommerceRefundTracking < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_orders, :refunded_cents, :integer, null: false, default: 0
    add_column :lightek_commerce_orders, :confirmation_sent_at, :datetime
    add_check_constraint :lightek_commerce_orders, "refunded_cents >= 0 AND refunded_cents <= total_cents", name: "commerce_refunded_amount_valid"
    create_table :lightek_commerce_refunds do |t|
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}
      t.integer :amount_cents, null: false
      t.string :processor_ref
      t.string :status, null: false, default: "pending"
      t.string :idempotency_key, null: false
      t.timestamps
    end
    add_index :lightek_commerce_refunds, :idempotency_key, unique: true
    add_index :lightek_commerce_refunds, :processor_ref, unique: true
    add_check_constraint :lightek_commerce_refunds, "amount_cents > 0", name: "commerce_refund_positive"
  end
end
