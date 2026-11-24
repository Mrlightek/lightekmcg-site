class CreateItServiceBusinessOperations < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_reservation_resources, :it_service_appointment, :boolean, default: false, null: false

    create_table :it_service_plans do |t|
      t.references :product, null: false, index: { unique: true }, foreign_key: { to_table: :lightek_commerce_products }
      t.references :resource, null: false, index: { unique: true }, foreign_key: { to_table: :lightek_reservation_resources }
      t.timestamps
    end

    create_table :it_service_memberships do |t|
      t.references :plan, null: false, foreign_key: { to_table: :it_service_plans }
      t.references :customer, null: false, foreign_key: { to_table: :users }
      t.references :order, null: false, index: { unique: true }, foreign_key: { to_table: :lightek_commerce_orders }
      t.timestamps
    end

    create_table :it_service_coverage_periods do |t|
      t.references :membership, null: false, foreign_key: { to_table: :it_service_memberships }
      t.references :invoice, null: false, index: { unique: true }, foreign_key: { to_table: :lightek_commerce_billing_invoices }
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.timestamps
    end

    create_table :it_service_coverage_claims do |t|
      t.references :period, null: false, foreign_key: { to_table: :it_service_coverage_periods }
      t.references :reservation, null: false, index: { unique: true }, foreign_key: { to_table: :lightek_reservations }
      # The IT request table ships in Batch B. The release check verifies that dependency.
      t.bigint :service_request_id, null: false
      t.timestamps
    end

    create_table :it_service_payouts do |t|
      t.bigint :service_request_id, null: false, index: { unique: true }
      t.references :employer, null: false, foreign_key: { to_table: :users }
      t.references :technician, null: false, foreign_key: { to_table: :users }
      t.references :prepared_by, null: false, foreign_key: { to_table: :users }
      t.references :pay_statement, null: false, foreign_key: { to_table: :lightek_people_pay_statements }
      t.integer :gross_cents, null: false
      t.timestamps
    end
  end
end
