# frozen_string_literal: true

class CreateLightekSalesPartners < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_sales_partners do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :product, null: false, foreign_key: {to_table: :lightek_commerce_products}
      t.string :name, null: false
      t.string :agreement_reference, null: false
      t.bigint :commission_cents, null: false
      t.string :referral_code, null: false
      t.datetime :revoked_at
      t.timestamps
      t.index :referral_code, unique: true
      t.check_constraint 'commission_cents > 0', name: 'sales_partner_positive_commission'
    end

    add_reference :website_template_inquiries, :sales_partner,
      foreign_key: {to_table: :lightek_sales_partners}

    create_table :lightek_sales_referrals do |t|
      t.references :partner, null: false, foreign_key: {to_table: :lightek_sales_partners}
      t.references :lead, null: false, index: {unique: true}, foreign_key: {to_table: :lightek_sales_leads}
      t.bigint :commission_cents, null: false
      t.references :order, index: {unique: true}, foreign_key: {to_table: :lightek_commerce_orders}
      t.references :recorded_by, foreign_key: {to_table: :users}
      t.string :payout_reference
      t.datetime :paid_at
      t.timestamps
      t.index :payout_reference, unique: true
      t.check_constraint 'commission_cents > 0', name: 'sales_referral_positive_commission'
    end
  end
end
