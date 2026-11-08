class CreateLightekResortReservations < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_reservation_resources do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.bigint :source_resource_id
      t.references :product, foreign_key: {to_table: :lightek_commerce_products}
      t.string :name, null: false
      t.text :description
      t.string :kind, null: false, default: 'service'
      t.string :timezone, null: false, default: 'America/New_York'
      t.integer :capacity, null: false, default: 1
      t.integer :duration_minutes, null: false, default: 60
      t.integer :buffer_minutes, null: false, default: 0
      t.integer :notice_minutes, null: false, default: 60
      t.integer :cancellation_hours, null: false, default: 24
      t.boolean :published, null: false, default: false
      t.jsonb :hours, null: false, default: {}
      t.string :location
      t.string :join_url
      t.string :template_key
      t.string :billing_interval, null: false, default: 'monthly'
      t.jsonb :accommodations, null: false, default: []
      t.jsonb :compute, null: false, default: {}
      t.integer :cost_floor_cents, null: false, default: 0
      t.timestamps
    end
    add_foreign_key :lightek_reservation_resources, :lightek_reservation_resources, column: :source_resource_id
    create_table :lightek_reservations do |t|
      t.references :resource, null: false, foreign_key: {to_table: :lightek_reservation_resources}
      t.references :customer, null: false, foreign_key: {to_table: :users}
      t.references :order, foreign_key: {to_table: :lightek_commerce_orders}
      t.string :reference, null: false
      t.string :checkout_key, null: false
      t.string :status, null: false, default: 'held'
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.datetime :blocks_from, null: false
      t.datetime :blocks_until, null: false
      t.integer :quantity, null: false, default: 1
      t.datetime :hold_until
      t.datetime :canceled_at
      t.text :notes
      t.jsonb :notification_keys, null: false, default: []
      t.jsonb :package_snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :lightek_reservations, :reference, unique: true
    add_index :lightek_reservations, [:customer_id, :checkout_key], unique: true
    add_index :lightek_reservations, :order_id, unique: true, where: 'order_id IS NOT NULL', name: 'idx_reservations_unique_order'
    add_index :lightek_reservations, [:resource_id, :blocks_from, :blocks_until], name: 'idx_reservations_availability'
    create_table :lightek_reservation_blackouts do |t|
      t.references :resource, null: false, foreign_key: {to_table: :lightek_reservation_resources}
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :reason
      t.timestamps
    end
    create_table :lightek_reservation_changes do |t|
      t.references :reservation, null: false, foreign_key: {to_table: :lightek_reservations}
      t.references :target_resource, null: false, foreign_key: {to_table: :lightek_reservation_resources}
      t.references :order, foreign_key: {to_table: :lightek_commerce_orders}
      t.string :status, null: false, default: 'quoted'
      t.integer :amount_cents, null: false
      t.datetime :effective_at, null: false
      t.datetime :expires_at, null: false
      t.jsonb :quote, null: false, default: {}
      t.text :error
      t.timestamps
    end
    add_index :lightek_reservation_changes, :order_id, unique: true, where: 'order_id IS NOT NULL', name: 'idx_reservation_changes_unique_order'
    add_column :lightek_commerce_orders, :payment_namespace, :string
    add_column :lightek_commerce_orders, :purpose, :string, null: false, default: 'purchase'
    add_column :lightek_commerce_orders, :stock_reserved, :boolean, null: false, default: true
    create_table :lightek_merchant_payout_schedules do |t|
      t.references :merchant, null: false, foreign_key: {to_table: :users}, index: {unique: true}
      t.string :cadence, null: false, default: 'biweekly'
      t.datetime :next_run_at, null: false
      t.datetime :last_run_at
      t.boolean :enabled, null: false, default: true
      t.text :last_error
      t.timestamps
    end
  end
end
