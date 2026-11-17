class CreatePwaCommercialRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_pwa_purchases do |t|
      t.references :user, null: false, foreign_key: true
      t.bigint :site_id, null: false
      t.bigint :order_id, null: false
      t.string :plan_key, null: false
      t.timestamps
    end
    add_index :lightek_pwa_purchases, :order_id, unique: true
    add_index :lightek_pwa_purchases, [:site_id, :user_id]
    add_foreign_key :lightek_pwa_purchases, :lightek_commerce_orders, column: :order_id
    create_table :lightek_pwa_youtube_revenues do |t|
      t.bigint :site_id, null: false
      t.references :user, null: false, foreign_key: true
      t.references :recorded_by, null: false, foreign_key: {to_table: :users}
      t.string :video_id, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :source_reference, null: false
      t.string :report_sha256, null: false
      t.bigint :views, null: false, default: 0
      t.bigint :amount_cents, null: false
      t.integer :creator_share_bps, null: false
      t.string :currency, null: false, default: 'usd'
      t.timestamps
    end
    add_index :lightek_pwa_youtube_revenues, [:site_id, :video_id, :period_start, :period_end], unique: true, name: 'pwa_youtube_period_unique'
  end
end
