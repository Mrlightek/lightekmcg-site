class CreateStudioBroadcastControl < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_broadcast_applications do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites, on_delete: :cascade}
      t.string :slug, null: false
      t.string :name, null: false
      t.string :platform, null: false, default: "roku"
      t.string :status, null: false, default: "draft"
      t.string :minimum_client_version, null: false, default: "1.0.0"
      t.jsonb :settings, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :studio_broadcast_applications, [:site_id, :slug], unique: true
    create_table :studio_broadcast_channels do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites, on_delete: :cascade}
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.string :playback_url
      t.string :image_url
      t.text :description
      t.integer :position, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    create_table :studio_broadcast_programs do |t|
      t.references :channel, null: false, foreign_key: {to_table: :studio_broadcast_channels, on_delete: :cascade}
      t.references :post, null: false, foreign_key: {on_delete: :cascade}
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.timestamps
    end
    add_index :studio_broadcast_programs, [:channel_id, :starts_at]
  end
end
