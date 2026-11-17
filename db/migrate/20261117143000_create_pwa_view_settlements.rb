class CreatePwaViewSettlements < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_pwa_view_batches do |t|
      t.references :site, null: false
      t.references :recorded_by, null: false, foreign_key: {to_table: :users}
      t.string :channel_id, null: false
      t.date :month, null: false
      t.string :currency, null: false, default: 'usd'
      t.bigint :finalized_cents, null: false
      t.bigint :estimated_micros, null: false
      t.bigint :creator_liability_cents, null: false
      t.string :source_reference, null: false
      t.string :report_sha256, null: false
      t.string :finalized_receipt_sha256, null: false
      t.string :state, null: false, default: 'reconciled'
      t.string :funding_reference, index: {unique: true}
      t.string :funding_balance_transaction
      t.string :platform_account
      t.bigint :funded_cents
      t.datetime :funded_at
      t.timestamps
    end
    add_index :lightek_pwa_view_batches, [:channel_id, :month], unique: true, name: 'pwa_channel_finalized_month'
    create_table :lightek_pwa_view_earnings do |t|
      t.references :view_batch, null: false, foreign_key: {to_table: :lightek_pwa_view_batches}
      t.references :user, null: false, foreign_key: true
      t.string :video_id, null: false
      t.bigint :views, null: false
      t.bigint :amount_cents, null: false
      t.string :state, null: false, default: 'awaiting_funding'
      t.string :destination_account
      t.string :transfer_reference, index: {unique: true}
      t.string :transfer_key, null: false, index: {unique: true}
      t.datetime :transfer_requested_at
      t.timestamps
    end
    add_index :lightek_pwa_view_earnings, [:view_batch_id, :user_id, :video_id], unique: true, name: 'pwa_finalized_creator_video'
  end
end
