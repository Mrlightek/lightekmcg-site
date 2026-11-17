class RecordPwaPaidRevenuePeriods < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_subscriptions, :current_period_start, :datetime
    create_table :lightek_pwa_revenue_periods do |t|
      t.bigint :purchase_id, null: false
      t.string :source_reference, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :creator_share_bps, null: false, default: 8000
      t.timestamps
    end
    add_foreign_key :lightek_pwa_revenue_periods, :lightek_pwa_purchases, column: :purchase_id
    add_index :lightek_pwa_revenue_periods, :source_reference, unique: true
    add_index :lightek_pwa_revenue_periods, [:purchase_id, :starts_at, :ends_at], name: 'pwa_paid_revenue_window'
  end
end
