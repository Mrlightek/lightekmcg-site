class CreateLightekAgencyTrials < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_agency_trials do |t|
      t.references :prospect, null: false, foreign_key: {to_table: :users}, index: {unique: true}
      t.references :operator, null: false, foreign_key: {to_table: :users}
      t.references :billing_site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :order, foreign_key: {to_table: :lightek_commerce_orders}, index: {unique: true}
      t.references :paid_order, foreign_key: {to_table: :lightek_commerce_orders}
      t.string :brand_name, null: false
      t.string :sample_client_name, default: 'Oak Street Books', null: false
      t.integer :sample_retail_dollars, default: 49, null: false
      t.datetime :expires_at, null: false
      t.datetime :activated_at
      t.datetime :paid_through
      t.timestamps
    end
  end
end
