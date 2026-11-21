# Host dependency fixtures; production OrderPlacement and commerce models run.
ActiveRecord::Schema.define do
  create_table(:lightek_commerce_products) do |t|
    t.references :site; t.string :name; t.string :slug; t.string :currency, default: 'usd'; t.bigint :price_cents, default: 1000
    t.boolean :published, default: true; t.string :product_type, default: 'service'; t.string :billing_interval, default: 'one_time'
    t.integer :inventory_quantity, default: 0; t.boolean :track_inventory, default: false; t.integer :source_hosting_package_id
    t.integer :subscription_plan_id; t.string :image_url; t.string :short_description; t.string :sku; t.integer :position
    t.decimal :shipping_weight_lb; t.integer :shipping_length_in; t.integer :shipping_width_in; t.integer :shipping_height_in
  end
  create_table(:lightek_commerce_product_variants) { |t| t.references :product; t.boolean :active; t.string :name; t.integer :price_cents; t.integer :inventory_quantity }
  create_table(:lightek_shipping_quotes) { |t| t.references :site }
  create_table(:hosting_packages) { |t| t.references :product; t.boolean :active }
  create_table(:lightek_commerce_orders) do |t|
    t.references :site; t.string :status, default: 'pending_payment'; t.string :customer_email; t.string :currency, default: 'usd'
    t.integer :total_cents, default: 0; t.integer :subtotal_cents, default: 0; t.integer :shipping_cents, default: 0; t.integer :refunded_cents, default: 0
    t.json :revenue_share_snapshot, default: []; t.string :payment_namespace; t.string :payment_provider; t.string :payment_reference
    t.string :purpose; t.integer :shipping_quote_id; t.integer :hosting_owner_id; t.integer :gatekeeper_application_launch_id
    t.datetime :paid_at; t.datetime :provisioned_at; t.datetime :fulfilled_at; t.string :fulfillment_reference; t.text :fulfillment_note
    t.boolean :stock_reserved, default: true; t.datetime :canceled_at
    t.datetime :deleted_at; t.string :provisioning_state
  end
  create_table(:lightek_commerce_order_items) { |t| t.references :order; t.references :product; t.references :variant; t.string :name; t.integer :quantity; t.integer :unit_price_cents; t.integer :line_total_cents; t.json :purchase_snapshot, default: {} }
end
class ApplicationRecord
  def self.has_many_attached(name) = define_method(name) { [] }
end
module LightekShipping
  class Quote < ApplicationRecord
    self.table_name = 'lightek_shipping_quotes'
  end
end
class HostingPackage < ApplicationRecord
  belongs_to :product, class_name: 'LightekCommerce::Product'
end
module LightekCommerce
  module RevenueSharing
    class Invalid < StandardError; end
    def self.snapshot_for(*) = []
  end
  module MerchantPayouts
    class Invalid < StandardError; end
    def self.fee_quote(*) = raise('Unexpected payout quote')
  end
  class ReservationExpiryJob
    def self.set(*) = self
    def self.perform_later(*) = nil
  end
end
require ROOT.join('app/services/lightek_commerce/payment_identity')
require ROOT.join('app/models/lightek_commerce/product')
module LightekCommerce
  class ProductVariant < ApplicationRecord
    self.table_name = 'lightek_commerce_product_variants'
    belongs_to :product
  end
end
require ROOT.join('app/models/lightek_commerce/order')
require ROOT.join('app/models/lightek_commerce/order_item')
require ROOT.join('app/services/lightek_commerce/order_placement')
require ROOT.join('db/migrate/20261115120100_add_sales_quotes')
AddSalesQuotes.new.migrate(:up)
require ROOT.join('app/models/lightek_sales/quote')
require ROOT.join('app/services/lightek_sales/quotes')
module LightekCommerce
  class StripeCheckout
    class Unavailable < StandardError; end
    def self.start!(**) = raise('Unexpected live checkout')
  end
end
LightekSales::Quote.signed_id_verifier = ActiveSupport::MessageVerifier.new('quote-fixture-only-' * 8)
