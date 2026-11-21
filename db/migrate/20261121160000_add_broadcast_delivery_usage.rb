class AddBroadcastDeliveryUsage < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_broadcast_delivery_usage do |t|
      t.bigint :site_id, null: false
      t.string :channel_key, null: false
      t.date :day, null: false
      t.bigint :bytes_served, null: false, default: 0
      t.bigint :encoding_ms, null: false, default: 0
      t.bigint :stored_bytes, null: false, default: 0
      t.bigint :support_minutes, null: false, default: 0
      t.index %i[site_id channel_key day], unique: true, name: "idx_broadcast_delivery_usage"
    end
    create_table :studio_broadcast_delivery_rates do |t|
      t.bigint :site_id, null: false, index: { unique: true }
      %i[egress storage encoding support].each { |column| t.decimal column, precision: 12, scale: 6, null: false }
      t.timestamps
    end
  end
end
