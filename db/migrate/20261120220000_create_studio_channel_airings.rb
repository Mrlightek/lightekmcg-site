class CreateStudioChannelAirings < ActiveRecord::Migration[8.0]
  def change
    add_column :studio_broadcast_channels, :managed_playout, :boolean, default: false, null: false
    create_table :studio_channel_airings do |t|
      t.references :channel, null: false, foreign_key: { to_table: :studio_broadcast_channels, on_delete: :cascade }
      t.references :operator, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.string :title, null: false
      t.string :relay
      t.string :status, default: "preparing", null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.jsonb :rundown, null: false, default: []
      t.jsonb :events, null: false, default: []
      t.jsonb :state, null: false, default: {}
      t.text :error_message
      t.timestamps
      t.index [:channel_id, :starts_at]
      t.index [:status, :starts_at]
    end
  end
end
