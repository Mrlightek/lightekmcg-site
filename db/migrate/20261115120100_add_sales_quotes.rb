class AddSalesQuotes < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_sales_quotes do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :opportunity, null: false, foreign_key: {to_table: :lightek_sales_opportunities}
      t.references :accepted_by, foreign_key: {to_table: :users}
      t.string :acceptance_channel
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.references :order, foreign_key: {to_table: :lightek_commerce_orders}, index: {unique: true}
      t.string :series_key, null: false
      t.integer :revision, null: false, default: 1
      t.string :status, null: false, default: 'draft'
      t.string :portal_host, null: false
      t.string :customer_email, null: false
      t.string :title, null: false
      t.string :currency, null: false, default: 'USD'
      t.bigint :total_cents, null: false, default: 0
      t.jsonb :lines, null: false, default: []
      t.text :terms
      t.date :expires_on, null: false
      t.datetime :issued_at
      t.datetime :accepted_at
      t.string :accepted_name
      t.string :acceptance_reference
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_sales_quotes, [:site_id, :series_key, :revision], unique: true, name: 'idx_sales_quote_revision'
  end
end
