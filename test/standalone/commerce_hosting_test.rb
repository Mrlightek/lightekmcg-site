# Actual commerce services and database transactions, with processor/provider calls
# replaced at their boundaries. Run without the private ecosystem dependencies.
gem "minitest", "~> 5.0"
require "minitest/autorun"
require "minitest/mock"
require "active_record"
require "active_job"
require "active_support/all"
require "action_dispatch/http/upload"
require "tempfile"
require "pathname"
require "ostruct"
require "uri"

module Rails
  def self.root = Pathname.new(File.expand_path("../..", __dir__))
  def self.logger = Logger.new(File::NULL)
  def self.cache = @cache ||= ActiveSupport::Cache::MemoryStore.new
end
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  def self.has_many_attached(name)
    define_method(name) do
      @test_attachments ||= {}
      @test_attachments[name] ||= Class.new(Array) { def attach(**value) = self << value }.new
    end
  end
end
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false
ActiveRecord::ConnectionAdapters::TableDefinition.class_eval { alias_method :jsonb, :json }
ActiveRecord::Schema.define do
  create_table(:lightek_pwa_platform_operators) { |t| t.integer :site_id; t.integer :operator_id }
  create_table(:users) { |t| t.string :role; t.string :email_address; t.string :stripe_connect_account_id; t.string :first_name; t.string :last_name; t.string :password; t.boolean :password_setup_required, default: false }
  create_table(:dymond_site_sites) { |t| t.string :host; t.string :name; t.references :tenant, polymorphic: true; t.json :manifest, default: {} }
  create_table(:gatekeeper_nodes) { |t| t.references :owner, polymorphic: true; t.string :status }
  create_table(:lightek_reservation_peers) { |t| t.references :site; t.references :merchant; t.string :key }
  create_table(:compute_providers) { |t| t.string :slug; t.string :health_status }
  create_table(:gatekeeper_application_templates) do |t|
    t.string :name; t.string :kind; t.integer :container_port, default: 3000; t.boolean :enabled, default: true
    t.string :build_status, default: "ready"; t.string :image; t.string :credential_slug
    t.boolean :rails_database, default: true; t.boolean :rails_worker, default: false
  end
  create_table(:gatekeeper_application_launches) { |t| t.references :gatekeeper_node }
  create_table(:dymond_bank_subscription_plans) do |t|
    t.string :name, :slug, :currency
    t.text :description
    t.integer :price_monthly_cents
    t.boolean :active
  end
  create_table(:dymond_bank_subscriptions) do |t|
    t.string :status; t.datetime :current_period_end; t.datetime :current_period_start; t.datetime :trial_ends_at
    t.references :subscriber, polymorphic: true; t.integer :plan_id
  end
  create_table(:subscription_infrastructure_entitlements) { |t| t.integer :subscription_plan_id; t.integer :max_sites }
  create_table(:lightek_commerce_products) do |t|
    t.references :site; t.string :name; t.text :description; t.string :slug; t.string :currency, default: "usd"
    t.integer :price_cents, default: 0; t.integer :inventory_quantity, default: 0
    t.boolean :published, default: true; t.string :product_type, default: "physical"
    t.integer :subscription_plan_id; t.string :image_url; t.string :short_description; t.string :sku; t.integer :position
    t.timestamps
  end
  create_table(:lightek_commerce_product_variants) do |t|
    t.references :product; t.string :name; t.string :sku; t.boolean :active, default: true; t.integer :price_cents; t.integer :inventory_quantity
    t.timestamps
  end
  create_table(:lightek_commerce_orders) do |t|
    t.references :site; t.string :status, default: "pending_payment"; t.string :customer_email
    t.string :currency, default: "usd"; t.integer :total_cents, default: 0; t.integer :subtotal_cents, default: 0
    t.integer :tax_cents, default: 0; t.integer :shipping_cents, default: 0; t.integer :refunded_cents, default: 0
    t.string :merchant_transfer_ref; t.integer :merchant_transfer_amount_cents; t.boolean :stock_reserved, default: true; t.string :payment_namespace; t.string :payment_reference; t.string :payment_provider
    t.string :client_checkout_key
    t.timestamps
    t.datetime :merchant_transfer_requested_at, :merchant_transfer_completed_at
    t.text :merchant_transfer_error
    t.datetime :confirmation_sent_at, :fulfillment_notification_sent_at
    t.datetime :fulfilled_at; t.string :fulfillment_reference; t.string :fulfillment_note; t.datetime :paid_at; t.datetime :canceled_at; t.datetime :provisioned_at; t.string :purpose
  end
  create_table(:lightek_commerce_refunds) do |t|
    t.references :order
    t.string :status, default: "pending"
    t.string :idempotency_key, :processor_ref
    t.integer :amount_cents
    t.timestamps
    t.index :idempotency_key, unique: true
  end
  create_table(:lightek_commerce_order_items) do |t|
    t.references :order; t.references :product; t.references :variant
    t.string :name; t.integer :quantity; t.integer :unit_price_cents; t.integer :line_total_cents
  end
end
source = Rails.root.join("db/migrate/20261112070000_connect_hosting_agencies_and_commerce.rb").read
source = source.sub("Migration[8.0]", "Migration[7.2]")
eval(source, TOPLEVEL_BINDING)
ConnectHostingAgenciesAndCommerce.new.migrate(:up)
eval(Rails.root.join("db/migrate/20261118001500_add_hosting_wholesale_prices.rb").read, TOPLEVEL_BINDING)
AddHostingWholesalePrices.new.migrate(:up)
source = Rails.root.join("db/migrate/20261112073000_add_nested_reseller_sale_shares.rb").read
source = source.sub("Migration[8.0]", "Migration[7.2]")
eval(source, TOPLEVEL_BINDING)
AddNestedResellerSaleShares.new.migrate(:up)
source = Rails.root.join("db/migrate/20261112080000_create_platform_shipping.rb").read
source = source.sub("Migration[8.0]", "Migration[7.2]")
eval(source, TOPLEVEL_BINDING)
CreatePlatformShipping.new.migrate(:up)
source = Rails.root.join("db/migrate/20261112083000_connect_federated_commerce_settlement.rb").read
eval(source.sub("Migration[8.0]", "Migration[7.2]"), TOPLEVEL_BINDING)
ConnectFederatedCommerceSettlement.new.migrate(:up)
require Rails.root.join("app/models/concerns/account_hierarchy").to_s
class User < ApplicationRecord
  def full_name = [first_name, last_name].compact.join(" ")
  belongs_to :agency, class_name: "User", optional: true
  has_many :agency_clients, class_name: "User", foreign_key: :agency_id
  has_one :agency_profile
  def white_label? = role == "white_label"
  include AccountHierarchy
  def stripe_connect_ready? = stripe_connect_account_id.present?
end
class GatekeeperNode < ApplicationRecord
  belongs_to :owner, polymorphic: true
end
class SubscriptionInfrastructureEntitlement < ApplicationRecord
  belongs_to :subscription_plan, class_name: "DymondBank::SubscriptionPlan"
end
class ComputeProvider < ApplicationRecord
  def self.active = all
end
module DymondSite
  class Site < ApplicationRecord
    self.table_name = "dymond_site_sites"
    belongs_to :tenant, polymorphic: true
  end
end
module DymondBank
  module StripeService
    def self.sync_connect_status!(*) = nil
    def self.create_transfer(*) = raise("Unexpected processor transfer")
  end
  class SubscriptionPlan < ApplicationRecord
    self.table_name = "dymond_bank_subscription_plans"
  end
  class Subscription < ApplicationRecord
    self.table_name = "dymond_bank_subscriptions"
    belongs_to :subscriber, polymorphic: true
  end
  module StripeCredentials
    def self.secret_key = "test-key"
  end
end
module Stripe
  class StripeError < StandardError; end
  class << self; attr_accessor :api_key; end
  class Account
    def self.retrieve(*) = raise("Unexpected connected account lookup")
  end
  class Payout
    def self.list(*) = raise("Unexpected payout list")
    def self.retrieve(*) = raise("Unexpected payout lookup")
  end
  class BalanceTransaction
    def self.list(*) = raise("Unexpected balance read")
  end
  class File
    def self.create(*) = raise("Unexpected evidence upload")
  end
  class Dispute
    def self.list(*) = raise("Unexpected dispute list")
    def self.retrieve(*) = raise("Unexpected dispute lookup")
    def self.update(*) = raise("Unexpected dispute response")
  end
  class PaymentIntent
    def self.create(*) = raise("Unexpected processor payment setup")
    def self.cancel(*) = raise("Unexpected processor payment cancellation")
    def self.retrieve(*) = raise("Unexpected processor payment intent")
  end
  module Tax
    class Calculation
      def self.create(*) = raise("Unexpected tax quote")
    end
    class Transaction
      def self.create_from_calculation(*) = raise("Unexpected tax transaction")
      def self.create_reversal(*) = raise("Unexpected tax reversal")
    end
  end
  class Refund
    def self.retrieve(*) = raise("Unexpected processor refund lookup")
    def self.create(*) = raise("Unexpected processor refund")
  end
  class Transfer
    def self.create_reversal(*) = raise("Unexpected transfer reversal")
  end
  module Checkout
    class Session
      def self.retrieve(*) = raise("Unexpected processor call")
      def self.create(*) = raise("Unexpected processor call")
      def self.list(*) = raise("Unexpected checkout list")
    end
  end
  class Invoice
    def self.retrieve(*) = raise("Unexpected processor call")
  end
  class Customer
    def self.create(*) = raise("Unexpected processor customer creation")
  end
  class Subscription
    def self.retrieve(*) = raise("Unexpected processor call")
  end
end
module LightekVault
  module Service
    def self.checkout!(*) = {"client_id" => "fake-client".dup, "client_secret" => "fake-secret".dup, "account_number" => "123456789".dup}
  end
end
module LightekReservations
  module Federation
    class Client
      class Unavailable < StandardError; end
      def self.config(*) = nil
      def initialize(*) = nil
      def request(*) = raise("Unexpected network call")
    end
  end
  class Peer < ApplicationRecord
    self.table_name = "lightek_reservation_peers"
    belongs_to :merchant, class_name: "User"
    belongs_to :site, class_name: "DymondSite::Site"
  end
  class Reservation
    def self.find_by(*) = nil
  end
  class Change
    def self.find_by(*) = nil
  end
  class Settlement
    def self.for_order!(*) = nil
  end
end
module LightekCommerce
  class ReservationExpiryJob
    def self.set(*) = self
    def self.perform_later(*) = nil
  end
  class FulfillmentNotificationJob
    def self.perform_later(*) = nil
  end
  class OrderConfirmationJob
    def self.perform_later(*) = nil
  end
  class PaidInstanceProvisioningJob
    def self.perform_later(*) = nil
  end
  class InstanceReadiness
    class Unavailable < StandardError; end
    def self.check!(*) = true
  end
end
source = Rails.root.join("db/migrate/20261114130000_add_agency_package_policies.rb").read
source = source.gsub('Migration[8.0]', "Migration[#{ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]")
eval(source, TOPLEVEL_BINDING)
AddAgencyPackagePolicies.new.migrate(:up)
require Rails.root.join('app/services/lightek_pwa/policy').to_s
require Rails.root.join('app/models/lightek_pwa/platform_operator').to_s
require Rails.root.join('app/services/lightek_agency/package_policy').to_s
require Rails.root.join('app/services/lightek_agency/hosting_catalog').to_s
%w[gatekeeper_application_template agency_profile hosting_package lightek_commerce/product
  lightek_commerce/network_account lightek_commerce/network_sale lightek_commerce/order lightek_commerce/order_item lightek_commerce/subscription lightek_commerce/billing_invoice lightek_commerce/revenue_allocation lightek_shipping/account lightek_shipping/profile lightek_shipping/quote lightek_shipping/shipment].each do |path|
  require Rails.root.join("app/models/#{path}").to_s
end
%w[lightek_commerce/network_accounts lightek_commerce/network_gateway lightek_commerce/network_checkout lightek_shipping/payload lightek_shipping/fedex lightek_shipping/ups lightek_shipping/quotes lightek_shipping/pickup_quote lightek_shipping/supplies lightek_shipping/purchases lightek_shipping/labels lightek_commerce/fulfillment gatekeeper/hosting/access lightek_commerce/payment_identity lightek_commerce/revenue_sharing lightek_commerce/merchant_payouts lightek_commerce/order_placement
  gatekeeper/compute/linode_catalog_service gatekeeper/hosting/package_purchase gatekeeper/hosting/workspace_plans gatekeeper/hosting/retail_pricing lightek_commerce/stripe_checkout lightek_commerce/stripe_events lightek_commerce/subscription_events lightek_commerce/refunds lightek_commerce/processor_payment lightek_commerce/buyer_price lightek_commerce/merchant_ledger lightek_settings/website_identity].each do |path|
  require Rails.root.join("app/services/#{path}").to_s
end
require Rails.root.join('db/migrate/20261114140000_add_commerce_order_deletion')
AddCommerceOrderDeletion.new.migrate(:up)
require Rails.root.join('db/migrate/20261127140000_add_commerce_buyer_fee_snapshot')
AddCommerceBuyerFeeSnapshot.new.migrate(:up)
require Rails.root.join('db/migrate/20261127160000_add_commerce_discounts')
AddCommerceDiscounts.new.migrate(:up)
require Rails.root.join('db/migrate/20261127161000_bind_storefront_orders_to_buyers')
BindStorefrontOrdersToBuyers.new.migrate(:up)
require Rails.root.join('db/migrate/20261127170000_create_commerce_gift_cards')
CreateCommerceGiftCards.new.migrate(:up)
%w[gift_card gift_redemption].each { |name| require Rails.root.join("app/models/lightek_commerce/#{name}") }
%w[gift_cards gift_checkout gift_refunds].each { |name| require Rails.root.join("app/services/lightek_commerce/#{name}") }
require Rails.root.join('db/migrate/20261127180000_extend_commerce_discount_rules')
ExtendCommerceDiscountRules.new.migrate(:up)
require Rails.root.join('db/migrate/20261127181000_create_commerce_collections')
CreateCommerceCollections.new.migrate(:up)
require Rails.root.join('db/migrate/20261127182000_add_commerce_quantity_promotions')
AddCommerceQuantityPromotions.new.migrate(:up)
require Rails.root.join('db/migrate/20261127183000_index_commerce_gift_card_store_scope')
IndexCommerceGiftCardStoreScope.new.migrate(:up)
require Rails.root.join('db/migrate/20261127184000_create_commerce_customer_segments')
CreateCommerceCustomerSegments.new.migrate(:up)
require Rails.root.join('db/migrate/20261127185000_record_merchant_funded_shipping_discounts')
RecordMerchantFundedShippingDiscounts.new.migrate(:up)
require Rails.root.join('db/migrate/20261127190000_add_commerce_gift_card_delivery')
AddCommerceGiftCardDelivery.new.migrate(:up)
require Rails.root.join('app/services/lightek_commerce/gift_delivery')
require Rails.root.join('db/migrate/20261127191000_add_provider_to_shipping_quotes')
AddProviderToShippingQuotes.new.migrate(:up)
require Rails.root.join('app/services/lightek_commerce/order_report')
require Rails.root.join('app/services/lightek_commerce/order_timeline')
require Rails.root.join('app/services/lightek_commerce/packing_slips')
require Rails.root.join('app/services/lightek_commerce/inventory_report')
require Rails.root.join('db/migrate/20261127192000_create_commerce_inventory_adjustments')
CreateCommerceInventoryAdjustments.new.migrate(:up)
require Rails.root.join('db/migrate/20261127193000_add_source_to_commerce_inventory_changes')
AddSourceToCommerceInventoryChanges.new.migrate(:up)
require Rails.root.join('db/migrate/20261127194000_record_order_inventory_changes')
RecordOrderInventoryChanges.new.migrate(:up)
require Rails.root.join('db/migrate/20261127195000_add_reason_to_commerce_inventory_changes')
AddReasonToCommerceInventoryChanges.new.migrate(:up)
require Rails.root.join('db/migrate/20261127200000_add_commerce_inventory_stock_states')
AddCommerceInventoryStockStates.new.migrate(:up)
require Rails.root.join('db/migrate/20261127201000_create_commerce_supplier_orders')
CreateCommerceSupplierOrders.new.migrate(:up)
require Rails.root.join('db/migrate/20261127202000_create_commerce_merchandise_returns')
CreateCommerceMerchandiseReturns.new.migrate(:up)
require Rails.root.join('db/migrate/20261127203000_link_commerce_refunds_to_returns')
LinkCommerceRefundsToReturns.new.migrate(:up)
require Rails.root.join('db/migrate/20261127204000_create_commerce_return_labels')
CreateCommerceReturnLabels.new.migrate(:up)
require Rails.root.join('db/migrate/20261127205000_add_commerce_return_fee')
AddCommerceReturnFee.new.migrate(:up)
require Rails.root.join('app/models/lightek_commerce/inventory_change')
require Rails.root.join('app/services/lightek_commerce/inventory_adjustment')
require Rails.root.join('app/services/lightek_commerce/inventory_stock_states')
require Rails.root.join('app/models/lightek_commerce/supplier_order')
require Rails.root.join('app/models/lightek_commerce/supplier_order_line')
require Rails.root.join('app/services/lightek_commerce/supplier_orders')
require Rails.root.join('app/models/lightek_commerce/merchandise_return')
require Rails.root.join('app/services/lightek_commerce/merchandise_returns')
require Rails.root.join('app/services/lightek_commerce/return_refunds')
require Rails.root.join('app/models/lightek_commerce/return_label')
require Rails.root.join('app/services/lightek_commerce/return_labels')
require Rails.root.join('app/services/lightek_commerce/refund_settlement')
require Rails.root.join('app/services/lightek_commerce/shipping_promotion')
require Rails.root.join('app/models/lightek_commerce/customer_segment')
require Rails.root.join('app/services/lightek_commerce/quantity_promotion')
require Rails.root.join('app/services/lightek_commerce/gift_liability')
require Rails.root.join('app/models/lightek_commerce/discount')
require Rails.root.join('app/models/lightek_commerce/discount_use')
require Rails.root.join('app/models/lightek_commerce/collection')
require Rails.root.join('app/services/lightek_commerce/discount_csv')
require Rails.root.join('app/services/lightek_commerce/discounts')
require Rails.root.join('app/services/lightek_commerce/store_appearance')
LightekCommerce::Order.reset_column_information
require Rails.root.join('app/services/lightek_payments/payout_accounts')
require Rails.root.join('app/services/lightek_commerce/bank_deposits')
require Rails.root.join('app/services/lightek_commerce/merchant_disputes')
require Rails.root.join('app/services/lightek_commerce/buyer_fees')
class ApplicationJob < ActiveJob::Base; end unless defined?(ApplicationJob)
require Rails.root.join('app/jobs/lightek_shipping/label_job')
require Rails.root.join('app/jobs/lightek_commerce/gift_delivery_job')
module LightekCommerce
  class OrderMailer
    def self.gift_delivered(*) = raise('Unexpected gift delivery')
  end
end
require Rails.root.join('app/jobs/lightek_commerce/buyer_fee_reversal_job')
require Rails.root.join('db/migrate/20261127150000_create_lightek_commerce_dispute_cases')
CreateLightekCommerceDisputeCases.new.migrate(:up)
require Rails.root.join('app/models/lightek_commerce/dispute_case')
require Rails.root.join('app/jobs/lightek_commerce/dispute_event_job')
module DymondDash
  class Notification
    def self.create!(*) = raise('Unexpected dispute notification')
  end
end
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(File::NULL)

module LightekCommerce
  class Refund < ApplicationRecord
    self.table_name = "lightek_commerce_refunds"
    belongs_to :order
  end
  class ProductVariant < ApplicationRecord
    self.table_name = "lightek_commerce_product_variants"
    belongs_to :product
  end
end

class CommerceHostingTest < Minitest::Test
  def setup
    Rails.cache.clear
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @operator = User.create!(role: "super_admin", email_address: "operator@example.com")
    @site = DymondSite::Site.create!(tenant: @operator, host: "shop.example.com")
  end
  def teardown = ActiveRecord::Base.connection.rollback_transaction
  def product(**attrs)
    LightekCommerce::Product.create!({site: @site, name: "Product", slug: SecureRandom.hex(8), price_cents: 2500,
      product_type: "service", billing_interval: "month", inventory_quantity: 0, track_inventory: false}.merge(attrs))
  end
  def order_for(product)
    LightekCommerce::OrderPlacement.call(site: @site, customer_email: "buyer@example.com", quantities: {product.id.to_s => 1})
  end
  def remote_subscription(order, **overrides)
    {"id" => "sub_1", "status" => "active", "customer" => "cus_1",
      "metadata" => LightekCommerce::PaymentIdentity.metadata(order).stringify_keys,
      "items" => {"data" => [{"quantity" => 1, "current_period_end" => 1.month.from_now.to_i,
        "price" => {"currency" => "usd", "unit_amount" => order.subtotal_cents, "recurring" => {"interval" => "month", "interval_count" => 1}}}]}}.merge(overrides.stringify_keys)
  end
  def register(order, data = remote_subscription(order))
    Stripe::Subscription.stub(:retrieve, data) do
      LightekCommerce::SubscriptionEvents.register!(order: order, session: OpenStruct.new(subscription: "sub_1"))
    end
  end

  def test_migration_creates_real_foreign_keys_and_unique_subscription_identity
    assert_includes LightekCommerce::Order.column_names, "gatekeeper_application_launch_id"
    assert_includes HostingPackage.column_names, "monthly_cost_ceiling_cents"
    first = register(order_for(product))
    other = order_for(product)
    second = LightekCommerce::Subscription.new(order: other, processor_reference: first.processor_reference, billing_interval: "month", amount_cents: 2500)
    refute second.valid?
  end
  def test_unlimited_subscription_reserves_no_physical_stock_and_cancel_does_not_inflate_stock
    service = product
    order = order_for(service)
    assert_equal 0, service.reload.inventory_quantity
    assert_equal "month", order.items.sole.purchase_snapshot["billing_interval"]
    LightekCommerce::OrderPlacement.cancel!(order)
    assert_equal 0, service.reload.inventory_quantity
  end
  def test_physical_inventory_is_restored_once_even_if_product_inventory_settings_change
    item = product(product_type: "physical", billing_interval: "one_time", track_inventory: true, inventory_quantity: 3)
    order = order_for(item)
    assert_equal 2, item.reload.inventory_quantity
    item.update!(track_inventory: false)
    2.times { LightekCommerce::OrderPlacement.cancel!(order) }
    assert_equal 3, item.reload.inventory_quantity
  end
  def test_recurring_and_one_time_carts_cannot_be_mixed_or_charge_multiple_subscription_units
    service = product
    physical = product(product_type: "physical", billing_interval: "one_time", inventory_quantity: 10)
    assert_raises(LightekCommerce::OrderPlacement::Invalid) do
      LightekCommerce::OrderPlacement.call(site: @site, customer_email: "buyer@example.com", quantities: {service.id.to_s => 1, physical.id.to_s => 1})
    end
    assert_equal 0, LightekCommerce::Order.count
    assert_equal 10, physical.reload.inventory_quantity
  end
  def test_other_store_products_cannot_enter_checkout
    other = DymondSite::Site.create!(tenant: @operator, host: "other.example.com")
    item = product(site: other)
    assert_raises(LightekCommerce::OrderPlacement::Invalid) { order_for(item) }
  end
  def test_checkout_uses_frozen_price_and_interval_after_product_changes
    item = product
    order = order_for(item)
    item.update!(price_cents: 9000, billing_interval: "year")
    Stripe::Checkout::Session.stub(:create, ->(params, options) {
      assert_equal "subscription", params[:mode]
      assert_equal "month", params[:line_items].sole[:price_data][:recurring][:interval]
      assert_equal 2500, params[:line_items].sole[:price_data][:unit_amount]
      assert_equal order.payment_namespace, params[:subscription_data][:metadata][:lightek_host_key]
      refute params.key?(:shipping_address_collection)
      assert options[:idempotency_key].include?(order.payment_namespace)
      OpenStruct.new(id: "cs_1")
    }) { LightekCommerce::StripeCheckout.start!(order: order, success_url: "https://shop.example.com/ok", cancel_url: "https://shop.example.com/cancel") }
  end
  def test_one_time_checkout_remains_payment_mode
    order = order_for(product(billing_interval: "one_time"))
    Stripe::Checkout::Session.stub(:create, ->(params, _) {
      assert_equal "payment", params[:mode]
      refute params.key?(:subscription_data)
      refute params[:line_items].sole[:price_data].key?(:recurring)
      OpenStruct.new(id: "cs_1")
    }) { LightekCommerce::StripeCheckout.start!(order: order, success_url: "https://example.com", cancel_url: "https://example.com") }
  end
  def test_embedded_checkout_is_the_default_with_matching_browser_credentials
    order = order_for(product(billing_interval: 'one_time'))
    prior = ENV.delete('LIGHTEK_COMMERCE_EMBEDDED_CHECKOUT')
    service = LightekCommerce::StripeCheckout
    service.stub(:embedded_publishable_key, 'pk_test_fixture') { assert service.embedded_for?(order) }
    service.stub(:embedded_publishable_key, -> { raise service::Unavailable }) { refute service.embedded_for?(order) }
    LightekCommerce::NetworkCheckout.stub(:connected?, true) do
      service.stub(:embedded_publishable_key, -> { flunk 'Federated checkouts do not use local credentials' }) do
        refute service.embedded_for?(order)
        assert service.embedded_for?(order, network: true)
        ENV['LIGHTEK_COMMERCE_EMBEDDED_CHECKOUT'] = 'false'
        refute service.embedded_for?(order, network: true)
      end
    end
  ensure
    ENV['LIGHTEK_COMMERCE_EMBEDDED_CHECKOUT'] = prior
  end

  def test_merchant_bank_deposit_matches_only_the_selected_merchants_orders
    %w[white_label client].each do |role|
      owner = User.create!(role: role, email_address: "#{role}@example.test", stripe_connect_account_id: "acct_#{role}")
      site = DymondSite::Site.create!(tenant: owner, host: "#{role}.example.com")
      order = LightekCommerce::OrderPlacement.call(site: site, customer_email: 'buyer@example.test',
        quantities: {product(site: site, billing_interval: 'one_time').id.to_s => 1})
      order.update!(merchant_transfer_ref: "tr_#{role}")
      assert_raises(ActiveRecord::RecordNotFound) { LightekCommerce::BankDeposits.new(site: site, actor: @operator) }

      connected = OpenStruct.new(id: "acct_#{role}", metadata: {lightek_user_id: owner.id.to_s})
      payout = OpenStruct.new(id: 'po_fixture', automatic: true, reconciliation_status: 'completed')
      Stripe::Account.stub(:retrieve, connected) do
        service = LightekCommerce::BankDeposits.new(site: site, actor: owner)
        Stripe::Payout.stub(:retrieve, ->(id, options) {
          assert_equal 'po_fixture', id
          assert_equal "acct_#{role}", options[:stripe_account]
          payout
        }) do
          Stripe::BalanceTransaction.stub(:list, ->(params, options) {
            assert_equal 'po_fixture', params[:payout]
            assert_equal "acct_#{role}", options[:stripe_account]
            OpenStruct.new(has_more: true, data: [{id: 'txn_sale', amount: 2_500, fee: 0, net: 2_500,
              currency: 'usd', reporting_category: 'transfer', source: {source_transfer: "tr_#{role}"}},
              {id: 'txn_adjustment', amount: -100, fee: 0, net: -100, currency: 'usd',
               reporting_category: 'adjustment', source: nil}])
          }) do
            detail = service.detail(id: payout.id)
            assert_equal order.id, detail[:rows].first[:order].id
            assert_nil detail[:rows].last[:order]
            assert_equal(-100, detail[:rows].last[:net_cents])
            assert_equal 'txn_adjustment', detail[:cursor]
          end
        end
      end
    end
  end

  def test_merchant_dispute_submission_requires_an_owned_open_dispute_and_confirmation
    order = order_for(product(billing_interval: 'one_time'))
    order.update!(status: 'paid', paid_at: Time.current, payment_provider: 'stripe', payment_reference: 'cs_dispute')
    session = {id: 'cs_dispute', payment_status: 'paid', currency: 'usd', amount_total: 2_500,
      payment_intent: 'pi_order', metadata: LightekCommerce::PaymentIdentity.metadata(order)}
    due = OpenStruct.new(due_by: 2.days.from_now.to_i, submission_count: 0)
    dispute = OpenStruct.new(id: 'dp_fixture', payment_intent: 'pi_order', currency: 'usd',
      amount: 2_500, status: 'needs_response', reason: 'product_not_received', evidence_details: due)
    Stripe::Checkout::Session.stub(:retrieve, session) do
      service = LightekCommerce::MerchantDisputes.new(order: order, actor: @operator)
      assert_raises(LightekCommerce::MerchantDisputes::Unavailable) do
        service.respond!(id: dispute.id, evidence: 'Delivered', confirmed: false)
      end
      Stripe::Dispute.stub(:retrieve, dispute) do
        dispute.payment_intent = 'pi_unrelated'
        assert_raises(ActiveRecord::RecordNotFound) { service.respond!(id: dispute.id, evidence: 'Delivered', confirmed: true) }
        dispute.payment_intent = 'pi_order'
        Stripe::Dispute.stub(:update, ->(id, payload, options) {
          assert_equal dispute.id, id
          assert_equal({evidence: {uncategorized_text: 'Delivered'}, submit: true}, payload)
          assert options[:idempotency_key].include?(order.payment_namespace)
          dispute
        }) { service.respond!(id: dispute.id, evidence: 'Delivered', confirmed: true) }
        due.submission_count = 1
        assert_raises(LightekCommerce::MerchantDisputes::Unavailable) do
          service.respond!(id: dispute.id, evidence: 'Delivered', confirmed: true)
        end
      end
    end
  end

  def test_store_dispute_job_records_current_status_and_alerts_once
    order = order_for(product(billing_interval: 'one_time'))
    order.update!(status: 'paid', paid_at: Time.current, payment_provider: 'stripe', payment_reference: 'cs_dispute')
    session = {id: 'cs_dispute', payment_status: 'paid', currency: 'usd', amount_total: 2_500,
      payment_intent: 'pi_order', metadata: LightekCommerce::PaymentIdentity.metadata(order)}
    dispute = OpenStruct.new(id: 'dp_new', payment_intent: 'pi_order', currency: 'usd', amount: 2_500,
      status: 'needs_response', reason: 'product_not_received', evidence_details: OpenStruct.new(due_by: 2.days.from_now.to_i))
    alerts = []
    DymondDash::Notification.stub(:create!, ->(**details) { alerts << details }) do
      Stripe::Checkout::Session.stub(:list, OpenStruct.new(data: [OpenStruct.new(id: 'cs_dispute')])) do
        Stripe::Checkout::Session.stub(:retrieve, session) do
          Stripe::Dispute.stub(:retrieve, dispute) do
            2.times { LightekCommerce::DisputeEventJob.new.perform(dispute.id) }
            assert_equal 'needs_response', LightekCommerce::DisputeCase.sole.status
            assert_equal @operator, alerts.sole[:recipient]
            dispute.status = 'won'
            LightekCommerce::DisputeEventJob.new.perform(dispute.id)
          end
        end
      end
    end
    assert_equal 'won', LightekCommerce::DisputeCase.sole.status
  end

  def test_evidence_upload_is_bound_to_an_owned_dispute_and_submitted_with_response
    order = order_for(product(billing_interval: 'one_time'))
    order.update!(status: 'paid', paid_at: Time.current, payment_provider: 'stripe', payment_reference: 'cs_upload')
    session = {id: 'cs_upload', payment_status: 'paid', currency: 'usd', amount_total: 2_500,
      payment_intent: 'pi_order', metadata: LightekCommerce::PaymentIdentity.metadata(order)}
    dispute = OpenStruct.new(id: 'dp_upload', payment_intent: 'pi_order', currency: 'usd', amount: 2_500,
      status: 'needs_response', reason: 'product_not_received',
      evidence_details: OpenStruct.new(due_by: 2.days.from_now.to_i, submission_count: 0))
    Tempfile.create('receipt') do |file|
      file.write('%PDF-1.4 fixture')
      file.rewind
      attachment = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'receipt.pdf')
      Stripe::Checkout::Session.stub(:retrieve, session) do
        service = LightekCommerce::MerchantDisputes.new(order: order, actor: @operator)
        Stripe::Dispute.stub(:retrieve, dispute) do
          Stripe::File.stub(:create, ->(payload, options) {
            assert_equal 'dispute_evidence', payload[:purpose]
            assert_equal '%PDF-1.4 fixture', payload[:file].read
            assert_includes options[:idempotency_key], dispute.id
            OpenStruct.new(id: 'file_receipt')
          }) do
            Stripe::Dispute.stub(:update, ->(_reference, payload, _) {
              assert_equal({evidence: {'receipt' => 'file_receipt'}, submit: true}, payload)
              dispute
            }) do
              service.respond!(id: dispute.id, evidence: '', confirmed: true, attachments: {'receipt' => attachment})
            end
          end
        end
      end
    end
  end

  def test_bank_export_walks_every_payout_and_transaction_page_with_utc_date_bounds
    @operator.update!(stripe_connect_account_id: 'acct_store')
    connected = OpenStruct.new(id: 'acct_store', metadata: {lightek_user_id: @operator.id.to_s})
    payout = OpenStruct.new(id: 'po_first', automatic: true, reconciliation_status: 'completed')
    manual = OpenStruct.new(id: 'po_manual', automatic: false, reconciliation_status: 'not_applicable')
    from = Date.new(2026, 11, 1)
    through = Date.new(2026, 11, 26)
    fetched = []
    Stripe::Account.stub(:retrieve, connected) do
      service = LightekCommerce::BankDeposits.new(site: @site, actor: @operator)
      Stripe::Payout.stub(:list, ->(query, options) {
        assert_equal({gte: Time.utc(2026, 11, 1).to_i, lt: Time.utc(2026, 11, 27).to_i}, query[:arrival_date])
        assert_equal 'acct_store', options[:stripe_account]
        assert_includes [nil, payout.id], query[:starting_after]
        query[:starting_after] ? OpenStruct.new(data: [manual], has_more: false) : OpenStruct.new(data: [payout], has_more: true)
      }) do
        Stripe::BalanceTransaction.stub(:list, ->(query, _) {
          assert_equal payout.id, query[:payout]
          id = query[:starting_after] ? 'txn_second' : 'txn_first'
          OpenStruct.new(data: [{id: id, amount: 100, fee: 0, net: 100, currency: 'usd'}], has_more: id == 'txn_first')
        }) do
          service.each_payout(from: from, through: through) do |record|
            fetched << record.id
            service.each_transaction(record) { |row| fetched << row[:id] }
          end
        end
      end
    end
    assert_equal %w[po_first txn_first txn_second po_manual], fetched
  end

  def test_embedded_checkout_uses_native_return_and_preserves_verified_settlement
    order = order_for(product(billing_interval: "one_time"))
    checkout = OpenStruct.new(id: "cs_embedded", status: "open", ui_mode: "embedded_page",
      client_secret: "fixture_secret", metadata: LightekCommerce::PaymentIdentity.metadata(order))
    LightekCommerce::StripeCheckout.stub(:embedded_publishable_key, "pk_test_fixture") do
      Stripe::Checkout::Session.stub(:create, ->(params, options) {
        assert_equal "embedded_page", params[:ui_mode]
        assert_equal "if_required", params[:redirect_on_completion]
        assert_equal "https://shop.example.com/ok", params[:return_url]
        refute params.key?(:success_url)
        refute params.key?(:cancel_url)
        assert_equal order.payment_namespace, params[:metadata][:lightek_host_key]
        assert_equal LightekCommerce::PaymentIdentity.key(order, "checkout"), options[:idempotency_key]
        checkout
      }) do
        assert_equal checkout, LightekCommerce::StripeCheckout.start!(order: order, embedded: true,
          success_url: "https://shop.example.com/ok", cancel_url: "https://shop.example.com/shop")
      end
    end
    assert_equal "cs_embedded", order.reload.payment_reference
    refute order.paid_at?
    Stripe::Checkout::Session.stub(:retrieve, checkout) do
      assert_equal checkout, LightekCommerce::StripeCheckout.resume!(order: order, embedded: true)
      checkout.metadata = checkout.metadata.merge(lightek_host_key: "wrong-installation")
      assert_raises(LightekCommerce::StripeCheckout::Unavailable) do
        LightekCommerce::StripeCheckout.resume!(order: order, embedded: true)
      end
    end
  end

  def test_buyer_price_rounds_up_to_the_next_even_dollar_and_recalculates_processing
    quote = LightekCommerce::BuyerPrice.quote(merchant_cents: 10_000, processor_bps: 300,
      processor_fixed_cents: 30)
    assert_equal({merchant_cents: 10_000, minimum_network_cents: 200, rounding_network_cents: 52,
      network_cents: 252, processor_reserve_cents: 348, buyer_cents: 10_600}, quote)

    odd = LightekCommerce::BuyerPrice.quote(merchant_cents: 10_100, processor_bps: 0, processor_fixed_cents: 0)
    assert_equal 10_400, odd[:buyer_cents]
    assert_equal 300, odd[:network_cents]

    already_even = LightekCommerce::BuyerPrice.quote(merchant_cents: 10_200, processor_bps: 0, processor_fixed_cents: 0)
    assert_equal 10_400, already_even[:buyer_cents]
    assert_equal 0, already_even[:rounding_network_cents]

    [1, 100, 2_500, 99_999].each do |principal|
      quote = LightekCommerce::BuyerPrice.quote(merchant_cents: principal, processor_bps: 290, processor_fixed_cents: 30)
      gross = quote.fetch(:buyer_cents)
      assert_equal 0, gross % 200
      assert_operator quote.fetch(:network_cents), :>=, 200
      assert_equal (gross * 290 + 9999).div(10_000) + 30, quote.fetch(:processor_reserve_cents)
      assert_equal principal, gross - quote.fetch(:network_cents) - quote.fetch(:processor_reserve_cents)
      lower_gross = gross - 200
      lower_processing = (lower_gross * 290 + 9999).div(10_000) + 30
      assert_operator lower_gross - lower_processing - principal, :<, 200
    end
    assert_raises(ArgumentError) { LightekCommerce::BuyerPrice.quote(merchant_cents: 0) }
    assert_raises(ArgumentError) { LightekCommerce::BuyerPrice.quote(merchant_cents: 100, processor_bps: 10_000) }
  end

  def test_buyer_fee_order_charges_confirmed_price_releases_principal_and_reverses_full_refund
    item = product(billing_interval: 'one_time', price_cents: 10_000)
    saved = ENV.to_h.slice('LIGHTEK_COMMERCE_BUYER_FEE_HOSTS', 'LIGHTEK_COMMERCE_BUYER_FEE_TAX_CODE',
      'LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED')
    ENV.update('LIGHTEK_COMMERCE_BUYER_FEE_HOSTS' => @site.host, 'LIGHTEK_COMMERCE_BUYER_FEE_TAX_CODE' => 'txcd_10000000',
      'LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED' => 'true')
    fee_math = ActiveSupport::MessageVerifier.new('fixture-signed-cart')
    fees = LightekCommerce::BuyerFees
    fee_quote = fees.quote_for(item)
    args = {site: @site, customer_email: 'buyer@example.com', quantities: {item.id.to_s => 1}, storefront: true}
    placer = LightekCommerce::OrderPlacement
    order = fees.stub(:verifier, fee_math) do
      assert_raises(fees::Invalid) { placer.call(**args) }
      token = fees.sign(@site, item, fee_quote)
      item.update!(price_cents: 10_500)
      assert_raises(fees::Invalid) { placer.call(**args, buyer_fee_token: token) }
      item.update!(price_cents: 10_000)
      created = placer.call(**args, buyer_fee_token: token)
      assert_equal created.id, placer.call(**args, buyer_fee_token: token).id
      assert_equal 1, LightekCommerce::Order.count
      created
    end
    assert_equal 10_000, order.subtotal_cents
    assert_equal 600, order.buyer_fee_cents
    assert_equal 10_600, order.total_cents
    assert_equal 10_000, LightekCommerce::MerchantPayouts.fee_quote(order)[:net_cents]

    Stripe::Checkout::Session.stub(:create, ->(params, _) {
      assert_equal [10_000, 600], params[:line_items].map { |item| item[:price_data][:unit_amount] }
      assert_equal 'txcd_10000000', params[:line_items].last.dig(:price_data, :product_data, :tax_code)
      OpenStruct.new(id: 'cs_buyer_fee')
    }) do
      LightekCommerce::StripeCheckout.start!(order: order, success_url: 'https://shop.example.com/ok',
        cancel_url: 'https://shop.example.com/shop')
    end

    session = OpenStruct.new(id: 'cs_buyer_fee', metadata: LightekCommerce::PaymentIdentity.metadata(order),
      currency: 'usd', mode: 'payment', payment_status: 'paid', amount_subtotal: 10_000, amount_total: 10_000,
      total_details: OpenStruct.new(amount_tax: 0, amount_shipping: 0))
    event = OpenStruct.new(type: 'checkout.session.completed', data: OpenStruct.new(object: session))
    assert_raises(LightekCommerce::StripeEvents::Rejected) { LightekCommerce::StripeEvents.process!(event) }
    refute order.reload.paid_at?
    session.amount_subtotal = 10_600
    session.amount_total = 10_600
    LightekCommerce::StripeEvents.process!(event)
    LightekCommerce::Fulfillment.complete!(order: order.reload, reference: 'delivered')
    @operator.update!(stripe_connect_account_id: 'acct_merchant')
    DymondBank::StripeService.stub(:create_transfer, ->(**params) {
      assert_equal 10_000, params[:amount_cents]
      assert_equal 'acct_merchant', params[:destination_account]
      OpenStruct.new(id: 'tr_buyerfee')
    }) { LightekCommerce::MerchantPayouts.request!(order: order, merchant: @operator) }
    assert_equal 10_000, order.reload.merchant_transfer_amount_cents
    assert_raises(LightekCommerce::Refunds::Invalid) { LightekCommerce::Refunds.issue!(order: order, amount_cents: 600) }

    Stripe::Checkout::Session.stub(:retrieve, {payment_intent: 'pi_buyerfee'}) do
      Stripe::Refund.stub(:create, ->(params, _) {
        assert_equal 10_600, params[:amount]
        OpenStruct.new(id: 're_buyerfee', status: 'succeeded')
      }) { LightekCommerce::Refunds.full!(order: order) }
    end
    assert_equal 'refunded', order.reload.status
    reversals = 0
    Stripe::Transfer.stub(:create_reversal, ->(reference, params, options) {
      reversals += 1
      assert_equal 'tr_buyerfee', reference
      assert_equal 10_000, params[:amount]
      assert_equal LightekCommerce::PaymentIdentity.key(order, 'buyer-fee-refund-v1'), options[:idempotency_key]
      OpenStruct.new(id: 'trr_buyerfee', amount: 10_000)
    }) do
      2.times { LightekCommerce::BuyerFeeReversalJob.new.perform(order.id) }
    end
    assert_equal 1, reversals
    assert_equal 'trr_buyerfee', order.reload.buyer_fee_reversal_ref
  ensure
    %w[LIGHTEK_COMMERCE_BUYER_FEE_HOSTS LIGHTEK_COMMERCE_BUYER_FEE_TAX_CODE LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED].each do |key|
      ENV[key] = saved[key] if saved
    end
  end

  def test_merchant_ledger_verifies_provider_fees_and_preserves_existing_order_and_refunds
    order = order_for(product(billing_interval: "one_time"))
    order.update!(status: "partially_refunded", paid_at: Time.current, payment_provider: "stripe",
      payment_reference: "cs_ledger", refunded_cents: 500, merchant_transfer_ref: "tr_ledger", merchant_transfer_amount_cents: 2_300)
    redirect = {id: "cs_ledger", payment_status: "paid", currency: "usd", amount_total: 2_500,
      payment_intent: "pi_ledger", metadata: LightekCommerce::PaymentIdentity.metadata(order)}
    balance = {source: "ch_ledger", amount: 2_500, fee: 103, net: 2_397, currency: "usd", status: "available"}
    charge = {id: "ch_ledger", payment_intent: "pi_ledger", paid: true, amount: 2_500,
      amount_refunded: 500, currency: "usd", disputed: false, balance_transaction: balance}
    intent = {id: "pi_ledger", status: "succeeded", currency: "usd", amount_received: 2_500, latest_charge: charge}
    other = User.create!(role: "super_admin", email_address: "other-operator@example.com")
    assert_raises(ActiveRecord::RecordNotFound) { LightekCommerce::MerchantLedger.read(order: order, actor: other, processor: true) }

    Stripe::Checkout::Session.stub(:retrieve, redirect) do
      Stripe::PaymentIntent.stub(:retrieve, intent) do
        info = LightekCommerce::MerchantLedger.read(order: order, actor: @operator, processor: true)
        assert_equal 103, info[:processor_actual_cents]
        assert_equal 2_397, info[:processor_net_cents]
        assert_equal 500, info[:processor_refunded_cents]
        assert_equal 500, info[:refunded_cents]
        assert_equal 2_300, info[:merchant_transfer_cents]
        assert_equal "available", info[:processor_funds_state]
        balance[:source] = "ch_unrelated"
        assert_raises(LightekCommerce::MerchantLedger::Invalid) do
          LightekCommerce::MerchantLedger.read(order: order, actor: @operator, processor: true)
        end
      end
      redirect[:metadata] = redirect[:metadata].merge(lightek_host_key: "invalid")
      assert_raises(LightekCommerce::MerchantLedger::Invalid) do
        LightekCommerce::MerchantLedger.read(order: order, actor: @operator, processor: true)
      end
    end
    assert_equal "partially_refunded", order.reload.status
    assert_equal "tr_ledger", order.merchant_transfer_ref
  end

  def test_gift_card_purchase_activates_only_after_stripe_and_holds_payout
    with_gift_store do
      purchase = LightekCommerce::GiftCards.purchase!(site: @site, buyer: @operator,
        customer_email: @operator.email_address, denomination: 2500)
      refute LightekCommerce::GiftCard.exists?(purchase_order: purchase)
      Stripe::Checkout::Session.stub(:create, ->(payload, _) {
        assert_equal 'txcd_10502000', payload.dig(:line_items, 0, :price_data, :product_data, :tax_code)
        OpenStruct.new(id: 'cs_gift_purchase')
      }) do
        LightekCommerce::StripeCheckout.start!(order: purchase, success_url: 'https://shop.example.com/ok',
          cancel_url: 'https://shop.example.com/shop')
      end
      session = OpenStruct.new(id: 'cs_gift_purchase', metadata: LightekCommerce::PaymentIdentity.metadata(purchase),
        currency: 'usd', livemode: false, mode: 'payment', payment_status: 'unpaid', amount_subtotal: 2500, amount_total: 2500,
        total_details: OpenStruct.new(amount_tax: 0, amount_shipping: 0))
      event = OpenStruct.new(type: 'checkout.session.completed', data: OpenStruct.new(object: session))
      LightekCommerce::StripeEvents.process!(event)
      assert_equal 'pending_payment', purchase.reload.status
      assert_empty LightekCommerce::GiftCard.where(purchase_order: purchase)
      session.payment_status = 'paid'
      deliveries = []
      LightekCommerce::OrderConfirmationJob.stub(:perform_later, ->(id) { deliveries << id }) do
        2.times { LightekCommerce::StripeEvents.process!(event) }
        purchase.update!(confirmation_sent_at: Time.current)
        LightekCommerce::StripeEvents.process!(event)
      end
      assert_equal [purchase.id, purchase.id], deliveries
      assert_equal 'fulfilled', purchase.reload.status
      card = LightekCommerce::GiftCard.find_by!(purchase_order: purchase)
      assert_equal 2500, card.available_cents
      assert_equal card.code_digest, LightekCommerce::GiftCard.digest(card.display_code)
      refute_includes card.encrypted_code, card.display_code
      assert_match(/held until redeemed/, LightekCommerce::MerchantPayouts.ineligible_reason(purchase))
    end
  end

  def test_gift_card_split_payment_and_refund_restore_original_tenders
    with_gift_store do
      card = funded_gift_card
      order = gift_merchandise_order(3000)
      intent = nil
      Stripe::Tax::Calculation.stub(:create, ->(payload, _) {
        assert_equal [3000], payload[:line_items].map { |line| line[:amount] }
        OpenStruct.new(id: 'taxcalc_gift', amount_total: 3300, tax_amount_exclusive: 300, currency: 'usd')
      }) do
        Stripe::PaymentIntent.stub(:create, ->(payload, _) {
          assert_equal 800, payload[:amount]
          intent = OpenStruct.new(**payload, id: 'pi_gift', status: 'requires_payment_method')
        }) do
          LightekCommerce::GiftCheckout.start!(order: order, code: card.display_code, address: gift_billing_address)
        end
      end
      assert_equal 0, card.reload.available_cents
      assert_equal 800, order.reload.cash_paid_cents
      assert_equal 'pending_payment', order.status
      intent.status = 'succeeded'
      intent.amount_received = 799
      assert_raises(LightekCommerce::GiftCheckout::Invalid) { LightekCommerce::GiftCheckout.settle_intent!(order, intent) }
      intent.amount_received = 800
      tax_entries = 0
      Stripe::Tax::Transaction.stub(:create_from_calculation, ->(data, _) {
        tax_entries += 1
        OpenStruct.new(id: 'tax_gift', reference: data[:reference], currency: 'usd')
      }) do
        event = OpenStruct.new(type: 'payment_intent.succeeded', data: OpenStruct.new(object: intent))
        2.times { LightekCommerce::StripeEvents.process!(event) }
      end
      assert_equal 1, tax_entries
      assert_equal 'paid', order.reload.status
      order.update!(status: 'fulfilled')
      assert_nil LightekCommerce::MerchantPayouts.ineligible_reason(order)
      @operator.update!(stripe_connect_account_id: 'acct_gift_store')
      transfer_due = LightekCommerce::MerchantPayouts.fee_quote(order).fetch(:net_cents)
      DymondBank::StripeService.stub(:create_transfer, ->(**data) {
        assert_equal transfer_due, data[:amount_cents]
        assert_equal 'acct_gift_store', data[:destination_account]
        OpenStruct.new(id: 'tr_gift_sale')
      }) { LightekCommerce::MerchantPayouts.request!(order: order, merchant: @operator) }
      assert_raises(LightekCommerce::Refunds::Invalid) { LightekCommerce::Refunds.full!(order: card.purchase_order) }
      Stripe::Refund.stub(:create, ->(data, _) {
        assert_equal 800, data[:amount]
        OpenStruct.new(**data, id: 're_gift', currency: 'usd', status: 'succeeded')
      }) do
        Stripe::Tax::Transaction.stub(:create_reversal, ->(data, _) {
          assert_equal 'tax_gift', data[:original_transaction]
          OpenStruct.new(id: 'tax_refunded', reference: data[:reference], currency: 'usd')
        }) do
          2.times { LightekCommerce::Refunds.full!(order: order) }
        end
      end
      assert_equal 2500, card.reload.available_cents
      assert_equal 3300, order.reload.refunded_cents
      assert_equal 2500, order.refunds.sole.gift_restore_cents
      Stripe::Transfer.stub(:create_reversal, ->(id, payload, _) {
        assert_equal 'tr_gift_sale', id
        assert_equal transfer_due, payload[:amount]
        OpenStruct.new(id: 'trr_gift_sale', amount: transfer_due)
      }) { 2.times { LightekCommerce::BuyerFeeReversalJob.new.perform(order.id) } }
      assert_equal 'trr_gift_sale', order.reload.buyer_fee_reversal_ref
    end
  end

  def test_gift_card_allows_partial_use_but_never_spends_pending_balance_twice
    with_gift_store do
      card = funded_gift_card
      first = gift_merchandise_order(1000)
      second = gift_merchandise_order(1900)
      Stripe::Tax::Calculation.stub(:create, ->(data, _) {
        OpenStruct.new(id: 'taxcalc_partial', amount_total: data[:line_items].sum { |line| line[:amount] },
          tax_amount_exclusive: 0, currency: 'usd')
      }) do
        Stripe::Tax::Transaction.stub(:create_from_calculation, ->(data, _) {
          OpenStruct.new(id: 'tax_partial', reference: data[:reference], currency: 'usd')
        }) do
          LightekCommerce::GiftCheckout.start!(order: first, code: card.display_code, address: gift_billing_address)
          assert_equal 'pending_payment', first.reload.status
          2.times { LightekCommerce::GiftCheckout.confirm!(first) }
        end
        assert_equal 1500, card.reload.available_cents
        assert_equal 'paid', first.reload.status
        assert_nil first.payment_reference
        Stripe::PaymentIntent.stub(:create, ->(data, _) {
          OpenStruct.new(**data, id: 'pi_expired', status: 'requires_payment_method')
        }) { LightekCommerce::GiftCheckout.start!(order: second, code: card.display_code, address: gift_billing_address) }
        assert_equal 0, card.reload.available_cents
        assert_raises(LightekCommerce::GiftCheckout::Invalid) do
          LightekCommerce::GiftCheckout.start!(order: gift_merchandise_order(900), code: card.display_code, address: gift_billing_address)
        end
      end
      intent = OpenStruct.new(id: 'pi_expired', amount: 400, currency: 'usd', status: 'requires_payment_method',
        metadata: LightekCommerce::PaymentIdentity.metadata(second).merge('lightek_gift_redemption' => '1'))
      Stripe::PaymentIntent.stub(:retrieve, intent) do
        Stripe::PaymentIntent.stub(:cancel, ->(id, _, _) {
          assert_equal 'pi_expired', id
          intent.status = 'canceled'
          intent
        }) { 2.times { LightekCommerce::GiftCheckout.expire!(second) } }
      end
      assert_equal 'canceled', second.reload.status
      assert_equal 1500, card.reload.available_cents
      assert_equal 'released', LightekCommerce::GiftRedemption.find_by!(order: second).state
    end
  end

  def test_gift_card_code_is_scoped_to_the_issuing_store_and_currency_mode
    with_gift_store do
      card = funded_gift_card
      order = gift_merchandise_order(2000)
      order.update!(gift_store_scope: 'different-store-same-operator')
      assert_raises(LightekCommerce::GiftCheckout::Invalid) do
        LightekCommerce::GiftCheckout.start!(order: order, code: card.display_code, address: gift_billing_address)
      end
      order.update!(gift_store_scope: nil)
      DymondBank::StripeCredentials.stub(:secret_key, 'sk_live_fixture') do
        assert_raises(LightekCommerce::GiftCheckout::Invalid) do
          LightekCommerce::GiftCheckout.start!(order: order, code: card.display_code, address: gift_billing_address)
        end
      end
      assert_equal 2500, card.reload.available_cents
    end
  end

  def with_gift_store
    keys = %w[LIGHTEK_COMMERCE_GIFT_CARDS_ENABLED LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED]
    previous = keys.to_h { |key| [key, ENV[key]] }
    ENV.update(keys.index_with { 'true' })
    @site.update!(manifest: {'commerce_gift_cards' => true})
    encryptor = ActiveSupport::MessageEncryptor.new('f' * 32, cipher: 'aes-256-gcm')
    LightekCommerce::GiftCard.stub(:encryptor, encryptor) { yield }
  ensure
    ENV.update(previous)
  end

  def funded_gift_card
    purchase = LightekCommerce::GiftCards.purchase!(site: @site, buyer: @operator,
      customer_email: @operator.email_address, denomination: 2500)
    purchase.update!(status: 'fulfilled', paid_at: Time.current)
    LightekCommerce::GiftCard.issue!(purchase, livemode: false)
  end

  def gift_merchandise_order(price)
    item = product(billing_interval: 'one_time', price_cents: price)
    LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.test',
      quantities: {item.id.to_s => 1}, storefront: true, storefront_buyer: @operator, gift_redemption: true)
  end

  def gift_billing_address = {line1: '123 Any St', city: 'Miami', state: 'FL', postal_code: '33101'}

  def test_discount_is_scoped_to_store_and_frozen_into_taxable_line_prices
    merchandise = product(billing_interval: 'one_time', price_cents: 1250)
    cart = {merchandise.id.to_s => 3}
    auto = LightekCommerce::Discount.create!(site: @site, name: 'Spring', kind: 'percent', amount: 10)
    code = LightekCommerce::Discount.create!(site: @site, name: 'Member', code: ' member ', kind: 'fixed', amount: 251)
    inputs = {site: @site, customer_email: 'buyer@example.test', quantities: cart, storefront: true}
    automatic = LightekCommerce::OrderPlacement.call(**inputs, expected_discount_cents: 375, storefront_buyer: @operator)
    assert_equal @operator.id, automatic.storefront_buyer_id
    assert_equal [375, 3375, auto.name], [automatic.discount_amount, automatic.subtotal_cents, automatic.discount_name]
    assert_raises(LightekCommerce::OrderPlacement::Invalid) do
      LightekCommerce::OrderPlacement.call(**inputs, discount_code: code.code, expected_discount_cents: 250)
    end
    discounted = LightekCommerce::OrderPlacement.call(**inputs, discount_code: 'member', expected_discount_cents: 251)
    assert_equal 3499, discounted.total_cents
    rows = LightekCommerce::Discounts.processor_items(discounted)
    assert_equal 3, rows.sum { |line| line.fetch(:quantity) }
    assert_equal 3499, rows.sum { |line| line[:price_data][:unit_amount] * line[:quantity] }
    foreign = DymondSite::Site.create!(tenant: @operator, host: 'other.example.com')
    assert_raises(LightekCommerce::Discounts::Invalid) do
      LightekCommerce::Discounts.quote(site: foreign, products: [merchandise], quantities: cart, code: 'member')
    end
  end

  def test_product_and_order_codes_freeze_line_allocations_and_combine_with_automatic_savings
    target = product(billing_interval: 'one_time', price_cents: 2000)
    other = product(billing_interval: 'one_time', price_cents: 3000)
    rules = LightekCommerce::Discount
    rules.create!(site: @site, target_product: target, name: 'Item', code: 'ITEM', kind: 'fixed', amount: 500, combinable: true)
    rules.create!(site: @site, name: 'Order', code: 'ORDER', kind: 'percent', amount: 10, combinable: true)
    rules.create!(site: @site, name: 'Automatic', kind: 'fixed', amount: 100, combinable: true)
    quantities = {target.id.to_s => 1, other.id.to_s => 1}
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.test',
      quantities: quantities, storefront: true, storefront_buyer: @operator, discount_code: %w[ORDER ITEM],
      expected_discount_cents: 1050)
    assert_equal 3950, order.total_cents
    allocations = order.items.to_h { |item| [item.product_id, item.purchase_snapshot.fetch('merchandise_discount_cents')] }
    assert_equal 683, allocations.fetch(target.id)
    assert_equal 367, allocations.fetch(other.id)
    assert_equal [100, 450, 500], LightekCommerce::DiscountUse.where(order: order).pluck(:amount_cents).sort
    assert_equal [1317, 2633], LightekCommerce::Discounts.processor_items(order).map { |line| line.dig(:price_data, :unit_amount) }
  end

  def test_manual_and_rule_based_collections_are_scoped_and_update_with_the_catalog
    low = product(name: 'Trial Class', billing_interval: 'one_time', price_cents: 100)
    high = product(name: 'Private Class', billing_interval: 'one_time', price_cents: 2000)
    foreign_site = DymondSite::Site.create!(tenant: @operator, host: 'foreign-collections.test')
    outsider = product(site: foreign_site, name: 'Foreign Class', billing_interval: 'one_time', price_cents: 2100)
    manual = LightekCommerce::Collection.create!(site: @site, name: 'New Products', product_ids: [high.id])
    assert_equal 'new-products', manual.slug
    assert_equal [high.id], manual.products.pluck(:id)
    refute manual.update(product_ids: [high.id, outsider.id])
    refute manual.published?
    assert_empty LightekCommerce::Collection.published.where(site: @site)
    collection = LightekCommerce::Collection.create!(site: @site, name: 'Classes', source: 'rules', published: true,
      conditions: [{'field' => 'name', 'operator' => 'contains', 'value' => 'CLASS'},
        {'field' => 'price_cents', 'operator' => 'at_least', 'value' => '500'}])
    assert_equal [high.id], collection.products.pluck(:id)
    collection.update!(matching: 'any')
    assert_equal [low.id, high.id], collection.products.order(:id).pluck(:id)
    collection.update!(matching: 'all')
    low.update!(price_cents: 600)
    high.update!(published: false)
    assert_equal [low.id], collection.products.merge(LightekCommerce::Product.visible).pluck(:id)
  end

  def test_collection_discount_applies_only_to_matching_lines_and_rejects_shared_targets
    target = product(billing_interval: 'one_time', price_cents: 2000)
    other = product(billing_interval: 'one_time', price_cents: 2500)
    collection = LightekCommerce::Collection.create!(site: @site, name: 'Limited selection', product_ids: [target.id])
    rules = LightekCommerce::Discount
    collection_rule = rules.create!(site: @site, target_collection: collection, name: 'Selection', code: 'GROUP',
      kind: 'percent', amount: 10, combinable: true)
    rules.create!(site: @site, target_product: target, name: 'Same item', code: 'ITEM', kind: 'fixed', amount: 50, combinable: true)
    inputs = {site: @site, products: [target, other], quantities: {target.id.to_s => 1, other.id.to_s => 1}}
    quote = LightekCommerce::Discounts.quote(**inputs, code: 'GROUP')
    assert_equal({target.id.to_s => 200, other.id.to_s => 0}, quote.line_savings)
    assert_raises(LightekCommerce::Discounts::Invalid) do
      LightekCommerce::Discounts.quote(**inputs, code: %w[ITEM GROUP])
    end
    collection.destroy!
    refute collection_rule.reload.active?
    assert_nil collection_rule.target_collection_id
  end

  def test_discount_segments_use_only_the_signed_in_buyers_settled_store_history
    item = product(billing_interval: 'one_time', price_cents: 2000)
    other_site = DymondSite::Site.create!(tenant: @operator, host: 'segment-other.test')
    segment = LightekCommerce::CustomerSegment.create!(site: @site, name: 'Repeat buyers', minimum_orders: 2,
      minimum_net_spend_cents: 3000)
    intro = LightekCommerce::CustomerSegment.create!(site: @site, name: 'First purchase', maximum_orders: 0)
    assert intro.includes_history?([0, 0])
    refute intro.includes_history?([1, 500])
    rules = LightekCommerce::Discount
    rule = rules.create!(site: @site, customer_segment: segment, name: 'Loyalty discount', code: 'LOYALTY',
      kind: 'fixed', amount: 200)
    refute rules.new(site: other_site, customer_segment: segment, name: 'Cross store', kind: 'fixed', amount: 200).valid?
    refute segment.destroy
    claim = {customer_email: @operator.email_address, storefront_buyer_id: @operator.id, subtotal_cents: 2200, total_cents: 2200}
    order = LightekCommerce::Order
    order.create!(**claim, site: other_site, paid_at: Time.current, status: 'fulfilled')
    order.create!(**claim, site: @site, paid_at: Time.current, status: 'fulfilled', purpose: 'gift_card_purchase')
    order.create!(**claim, site: @site, status: 'pending_payment')
    order.create!(**claim, site: @site, paid_at: Time.current, status: 'fulfilled')
    inputs = {site: @site, products: [item], quantities: {item.id.to_s => 1}, code: rule.code}
    discounts = LightekCommerce::Discounts
    assert_raises(discounts::Invalid) { discounts.quote(**inputs, buyer_id: @operator.id) }
    partial = order.create!(**claim, site: @site, paid_at: Time.current, status: 'partially_refunded', refunded_cents: 900)
    assert_equal 200, discounts.quote(**inputs, buyer_id: @operator.id).total
    assert_raises(discounts::Invalid) { discounts.quote(**inputs, buyer_id: nil) }
    partial.update!(status: 'refunded', refunded_cents: 2200)
    assert_raises(discounts::Invalid) { discounts.quote(**inputs, buyer_id: @operator.id) }
  end

  def test_scheduled_gift_card_delivery_waits_for_funding_and_delivers_once
    with_gift_store do
      Time.use_zone('Eastern Time (US & Canada)') do
        cards = LightekCommerce::GiftCards
        receiver = 'Recipient@example.test'
        inputs = {site: @site, buyer: @operator, customer_email: @operator.email_address, denomination: 2500,
          recipient_email: receiver}
        assert_raises(cards::Invalid) { cards.purchase!(**inputs, delivery_date: Date.current.prev_day.iso8601) }
        assert_raises(cards::Invalid) { cards.purchase!(**inputs.merge(recipient_email: 'not-an-email')) }
        order = cards.purchase!(**inputs, delivery_date: (Date.current + 2).iso8601)
        assert_equal receiver, order.gift_recipient_email
        assert_equal 9, order.gift_deliver_at.in_time_zone.hour
        job = LightekCommerce::GiftDeliveryJob.new
        job.perform(order.id)
        refute order.reload.gift_delivered_at?

        order.update!(status: 'fulfilled', paid_at: Time.current)
        LightekCommerce::GiftCard.issue!(order, livemode: false)
        job.perform(order.id)
        refute order.reload.gift_delivered_at?

        message = Minitest::Mock.new
        message.expect(:deliver_now, true)
        LightekCommerce::OrderMailer.stub(:gift_delivered, ->(id) {
          assert_equal order.id, id
          message
        }) do
          Time.stub(:current, order.gift_deliver_at + 1.second) do
            job.perform(order.id)
            job.perform(order.id)
          end
        end
        message.verify
        assert order.reload.gift_delivered_at?
      end
    end
  end

  def test_scheduled_gift_card_delivery_excludes_revoked_cards
    with_gift_store do
      order = LightekCommerce::GiftCards.purchase!(site: @site, buyer: @operator, customer_email: @operator.email_address,
        denomination: 2500, recipient_email: 'recipient@example.test')
      order.update!(status: 'fulfilled', paid_at: Time.current)
      card = LightekCommerce::GiftCard.issue!(order, livemode: false)
      card.update!(revoked_at: Time.current, available_cents: 0)
      LightekCommerce::GiftDeliveryJob.new.perform(card.purchase_order_id)
      refute card.purchase_order.reload.gift_delivered_at?
    end
  end

  def test_gift_card_liability_reconciles_available_reserved_refunded_and_voided_value
    with_gift_store do
      card = funded_gift_card
      card.update!(available_cents: 1400, disputed_at: Time.current)
      [{amount_cents: 500, state: 'held'}, {amount_cents: 600, state: 'captured'},
        {amount_cents: 300, state: 'refunded'}, {amount_cents: 150, state: 'released'}].each do |entry|
        LightekCommerce::GiftRedemption.create!(order: gift_merchandise_order(entry[:amount_cents]), gift_card: card,
          cash_cents: 0, tax_calculation: 'fixture', **entry)
      end
      funded_gift_card.update!(available_cents: 0, revoked_at: Time.current)
      funded_gift_card.update!(livemode: true)
      service = LightekCommerce::GiftLiability
      reports = service.for_store(@site)
      totals = reports.fetch('Store ledger').fetch('test')
      assert_equal [2, 5000, 2500, 1400, 500, 900, 300, 1900, 1900], totals.values_at(*service::FIELDS.keys)
      assert_equal 2500, reports.dig('Store ledger', 'live', 'outstanding_cents')
      assert_equal 1900, totals['face_cents'] - totals['voided_cents'] - totals['redeemed_cents'] + totals['restored_cents']
      csv = service.summary_csv(reports, generated_at: Time.current)
      assert_equal %w[live test], CSV.parse(csv, headers: true).map { |row| row['payment_mode'] }
      refute_includes csv, card.display_code
    end
  end

  def test_network_gift_card_liability_is_scoped_without_creating_merchant_accounts
    with_gift_store do
      key = 'a' * 64
      peer = Struct.new(:id).new(99)
      cards = LightekCommerce::GiftCards
      service = LightekCommerce::GiftLiability
      funded_gift_card.update!(store_scope: cards.network_scope(peer, key))
      funded_gift_card.update!(store_scope: cards.network_scope(peer, 'b' * 64))
      funded_gift_card.update!(store_scope: cards.network_scope(Struct.new(:id).new(100), key))
      assert_equal 2500, service.for_peer(peer, key).dig('test', 'outstanding_cents')
      assert_equal 0, service.for_peer(peer, 'c' * 64).dig('test', 'outstanding_cents')
      assert_raises(ArgumentError) { service.for_peer(peer, 'not-a-scope') }
      assert_equal 0, service.for_store(@site).dig('Store ledger', 'test', 'outstanding_cents')
    end
  end

  def test_buy_x_get_y_counts_distinct_units_and_rewards_the_least_expensive_items
    product = product(billing_interval: 'one_time', price_cents: 2000)
    blue = product.variants.create!(name: 'Blue', price_cents: 2000, inventory_quantity: 5)
    red = product.variants.create!(name: 'Red', price_cents: 1000, inventory_quantity: 5)
    blue_key = "#{product.id}:#{blue.id}"
    red_key = "#{product.id}:#{red.id}"
    rule = LightekCommerce::Discount.create!(site: @site, target_product: product, name: 'BOGO', code: 'BOGO',
      kind: 'buy_x_get_y', amount: 100, reward_type: 'percent', buy_quantity: 1, get_quantity: 1)
    inputs = {site: @site, products: [product], code: rule.code}
    assert_raises(LightekCommerce::Discounts::Invalid) do
      LightekCommerce::Discounts.quote(**inputs, quantities: {blue_key => 1})
    end

    quantities = {blue_key => 2, red_key => 2}
    quote = LightekCommerce::Discounts.quote(**inputs, quantities: quantities)
    assert_equal({blue_key => 0, red_key => 2000}, quote.line_savings)
    rule.update!(applications_per_order: 1)
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: @operator.email_address,
      quantities: quantities, storefront: true, storefront_buyer: @operator, discount_code: rule.code, expected_discount_cents: 1000)
    assert_equal 5000, order.total_cents
    assert_equal [2000, 500], LightekCommerce::Discounts.processor_items(order).map { |line| line.dig(:price_data, :unit_amount) }
    assert_equal 1000, LightekCommerce::DiscountUse.find_by!(order: order, discount: rule).amount_cents
  end

  def test_buy_x_get_y_combines_an_overlapping_qualifying_collection_with_order_discount
    qualifier = product(name: 'Qualifying', billing_interval: 'one_time', price_cents: 1200)
    reward = product(name: 'Reward', billing_interval: 'one_time', price_cents: 600)
    collection = LightekCommerce::Collection.create!(site: @site, name: 'Qualified', product_ids: [qualifier.id, reward.id])
    discounts = LightekCommerce::Discount
    discounts.create!(site: @site, name: 'Reward', target_product: reward, qualifying_collection: collection,
      kind: 'buy_x_get_y', reward_type: 'fixed', amount: 200, buy_quantity: 2, get_quantity: 1, combinable: true)
    discounts.create!(site: @site, name: 'Order', code: 'ORDER', kind: 'percent', amount: 10, combinable: true)
    inputs = {site: @site, products: [qualifier, reward], code: 'ORDER'}
    below_minimum = LightekCommerce::Discounts.quote(**inputs, quantities: {qualifier.id.to_s => 1, reward.id.to_s => 1})
    assert_equal [180], below_minimum.entries.map(&:last)

    # One reward unit qualifies, and the other gets the discount.
    quote = LightekCommerce::Discounts.quote(**inputs, quantities: {qualifier.id.to_s => 1, reward.id.to_s => 2})
    assert_equal [200, 220], quote.entries.map(&:last)
    assert_equal({qualifier.id.to_s => 120, reward.id.to_s => 300}, quote.line_savings)
  end

  def test_discount_csv_import_is_scoped_and_atomic_and_exports_spreadsheet_safe_data
    service = LightekCommerce::DiscountCSV
    product = product(name: 'Sample', billing_interval: 'one_time', price_cents: 999)
    other_site = DymondSite::Site.create!(tenant: @operator, host: 'discount-csv-other.test')
    assert_equal service::HEADERS, CSV.parse(service.export(other_site)).sole
    values = ['CSV', '=Sample', 'fixed', '150', '100', 'true', 'true', '2026-11-27T17:15:00Z',
      '2026-11-29T17:15:00Z', '10', '1', product.slug, nil]
    missing_target = values.dup
    missing_target[0] = 'WRONG'
    missing_target[11] = 'does-not-exist'
    headers = CSV.generate_line(service::ORIGINAL_HEADERS)
    row = CSV.generate_line(values)
    failure = headers + row + CSV.generate_line(missing_target)
    assert_raises(service::Invalid) { service.import!(@site, failure) }
    refute LightekCommerce::Discount.exists?(site: @site, code: 'CSV')

    assert_equal 1, service.import!(@site, headers + row)
    discount = LightekCommerce::Discount.find_by!(site: @site, code: 'CSV')
    assert_equal [true, true, 10, 1, product.id], [discount.active?, discount.combinable?,
      discount.usage_limit, discount.buyer_limit, discount.target_product_id]
    assert_equal "2026-11-27T17:15:00Z", discount.starts_at.utc.iso8601
    export = CSV.parse(service.export(@site), headers: true)
    assert_equal "'=Sample", export.first.fetch('name')
    assert_raises(service::Invalid) { service.import!(other_site, service.export(@site)) }
    assert_raises(service::Invalid) { service.import!(@site, headers + row) }
    assert_equal 1, LightekCommerce::Discount.where(code: 'CSV').count
  end

  def test_discount_review_rejects_repriced_carts_and_retries_a_reserved_discount
    item = product(billing_interval: 'one_time', price_cents: 2000)
    rule = LightekCommerce::Discount.create!(site: @site, name: 'Reviewed', code: 'REVIEW',
      kind: 'fixed', amount: 200, buyer_limit: 1)
    cart = {item.id.to_s => 1}
    discounts = LightekCommerce::Discounts
    verifier = ActiveSupport::MessageVerifier.new('fixture-signed-discount')
    discounts.stub(:verifier, verifier) do
      quote = discounts.quote(site: @site, products: [item], quantities: cart, code: rule.code, buyer_id: @operator.id)
      inputs = {site: @site, customer_email: @operator.email_address, quantities: cart, storefront: true,
        storefront_buyer: @operator, discount_code: rule.code, expected_discount_cents: 200,
        discount_review_token: discounts.signed_quote(@site, quote)}
      item.update!(price_cents: 2100)
      assert_raises(LightekCommerce::OrderPlacement::Invalid) { LightekCommerce::OrderPlacement.call(**inputs) }
      item.update!(price_cents: 2000)
      original = LightekCommerce::OrderPlacement.call(**inputs)
      assert_equal 1800, original.total_cents
      assert_equal original.id, LightekCommerce::OrderPlacement.call(**inputs).id
      assert_raises(LightekCommerce::OrderPlacement::Invalid) do
        LightekCommerce::OrderPlacement.call(**inputs.merge(quantities: {item.id.to_s => 2}))
      end
      assert_equal 1, LightekCommerce::DiscountUse.where(discount: rule).count
    end
  end

  def test_removing_an_unsold_target_product_deactivates_its_discount
    item = product(billing_interval: 'one_time', price_cents: 2000)
    rule = LightekCommerce::Discount.create!(site: @site, name: 'Target', target_product: item,
      kind: 'fixed', amount: 200)
    item.destroy!
    refute rule.reload.active?
    assert_nil rule.target_product_id
  end

  def test_discount_schedule_and_durable_limits_follow_checkout_state
    product = product(billing_interval: 'one_time', price_cents: 2000)
    row = LightekCommerce::Discount.create!(site: @site, name: 'Limited', code: 'LIMIT', kind: 'fixed', amount: 200,
      starts_at: 1.hour.from_now, ends_at: 2.hours.from_now, usage_limit: 1, buyer_limit: 1)
    inputs = {site: @site, customer_email: 'buyer@example.test', quantities: {product.id.to_s => 1}, storefront: true,
      storefront_buyer: @operator, discount_code: 'LIMIT', expected_discount_cents: 200}
    assert_raises(LightekCommerce::OrderPlacement::Invalid) { LightekCommerce::OrderPlacement.call(**inputs) }
    row.update!(starts_at: 1.hour.ago)
    original = LightekCommerce::OrderPlacement.call(**inputs)
    assert_raises(LightekCommerce::OrderPlacement::Invalid) { LightekCommerce::OrderPlacement.call(**inputs) }
    LightekCommerce::OrderPlacement.cancel!(original)
    assert_equal 1800, LightekCommerce::OrderPlacement.call(**inputs).total_cents
    row.update!(ends_at: 1.minute.ago)
    assert_raises(LightekCommerce::OrderPlacement::Invalid) { LightekCommerce::OrderPlacement.call(**inputs) }
  end

  def test_store_appearance_updates_only_the_commerce_manifest
    @site.update!(manifest: {'pages' => ['home']})
    LightekCommerce::StoreAppearance.save!(@site, {'brand_name' => '  Lightek  ', 'accent_color' => '#4655aa'})
    assert_equal ['home'], @site.reload.manifest['pages']
    assert_equal({'brand_name' => 'Lightek', 'accent_color' => '#4655aa'}, LightekCommerce::StoreAppearance.read(@site))
    assert_raises(LightekCommerce::StoreAppearance::Invalid) do
      LightekCommerce::StoreAppearance.save!(@site, {'accent_color' => 'url(invalid)'})
    end
  end

  def test_buyer_fee_cart_signs_variant_price_and_quantities_as_one_purchase
    physical = product(product_type: 'physical', billing_interval: 'one_time')
    variant = physical.variants.create!(name: 'Blue', price_cents: 1700, inventory_quantity: 4)
    digital = product(product_type: 'digital', billing_interval: 'one_time', price_cents: 900)
    cart = {"#{physical.id}:#{variant.id}" => 2, digital.id.to_s => 1}
    with_buyer_fee_configuration do |fees|
      lines, quote = fees.cart_price(products: [physical, digital], requested: cart)
      token = fees.sign(@site, lines, quote)
      inputs = {site: @site, customer_email: 'buyer@example.com', quantities: cart, storefront: true, buyer_fee_token: token}
      variant.update!(price_cents: 1600)
      digital.update!(price_cents: 1100)
      assert_raises(fees::Invalid) { LightekCommerce::OrderPlacement.call(**inputs) }
      variant.update!(price_cents: 1700)
      digital.update!(price_cents: 900)
      order = LightekCommerce::OrderPlacement.call(**inputs)
      assert_equal 4300, order.subtotal_cents
      assert_equal quote.fetch('buyer_cents'), order.total_cents
      assert_equal 4300, LightekCommerce::MerchantPayouts.fee_quote(order)[:net_cents]
      assert_equal 2, variant.reload.inventory_quantity
    end
  end

  def test_subscription_renews_at_frozen_buyer_price_and_keeps_merchant_principal
    item = product
    with_buyer_fee_configuration do |fees|
      cart = {item.id.to_s => 1}
      lines, quote = fees.cart_price(products: [item], requested: cart)
      order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.com', quantities: cart,
        storefront: true, buyer_fee_token: fees.sign(@site, lines, quote))
      Stripe::Checkout::Session.stub(:create, ->(payload, _) {
        assert_equal %w[month month], payload[:line_items].map { |row| row.dig(:price_data, :recurring, :interval) }
        OpenStruct.new(id: 'cs_renewal')
      }) do
        LightekCommerce::StripeCheckout.start!(order: order, success_url: 'https://shop.example.com/ok', cancel_url: 'https://shop.example.com/shop')
      end
      remote = remote_subscription(order)
      assert_raises(LightekCommerce::StripeEvents::Rejected) { register(order, remote) }
      recurring = remote['items']['data']
      fee_line = recurring.first.deep_dup
      fee_line['price']['unit_amount'] = order.buyer_fee_cents
      recurring.unshift(fee_line)
      subscription = register(order, remote)
      rows = [order.subtotal_cents, order.buyer_fee_cents].map { |amount| {'amount' => amount, 'currency' => 'usd', 'quantity' => 1} }
      total = order.total_cents
      invoice = {'id' => 'in_repeat', 'billing_reason' => 'subscription_cycle', 'status' => 'paid', 'currency' => 'usd',
        'subtotal' => total, 'total' => total, 'amount_paid' => total, 'lines' => {'data' => rows, 'has_more' => false}}
      receipt = LightekCommerce::SubscriptionEvents.record_invoice!(subscription: subscription, invoice: invoice, at: Time.current)
      renewal = receipt.settlement_order
      assert_equal 2500, renewal.subtotal_cents
      assert_equal total, renewal.total_cents
      assert_equal order.buyer_fee_breakdown, renewal.buyer_fee_breakdown
      assert_equal 2500, LightekCommerce::MerchantPayouts.fee_quote(renewal)[:net_cents]
      rows.first['amount'] -= 1
      rows.last['amount'] += 1
      mismatch = LightekCommerce::SubscriptionEvents.record_invoice!(subscription: subscription,
        invoice: invoice.merge('id' => 'in_mismatch'), at: Time.current)
      assert_nil mismatch.settlement_order
    end
  end

  def with_buyer_fee_configuration
    keys = %w[LIGHTEK_COMMERCE_BUYER_FEE_HOSTS LIGHTEK_COMMERCE_BUYER_FEE_TAX_CODE]
    prior = keys.to_h { |key| [key, ENV[key]] }
    ENV.update(keys.zip([@site.host, 'txcd_10000000']).to_h)
    fees = LightekCommerce::BuyerFees
    fees.stub(:verifier, ActiveSupport::MessageVerifier.new('fixture-cart-quote')) { yield fees }
  ensure
    ENV.update(prior)
  end

  def test_processor_subscription_must_match_order_namespace_price_and_interval
    order = order_for(product)
    assert_raises(LightekCommerce::StripeEvents::Rejected) { register(order, remote_subscription(order, metadata: {})) }
    bad = remote_subscription(order)
    bad["items"]["data"].first["price"]["unit_amount"] = 1
    assert_raises(LightekCommerce::StripeEvents::Rejected) { register(order, bad) }
    assert_equal 0, LightekCommerce::Subscription.count
  end
  def test_repeated_checkout_confirmation_registers_one_subscription
    order = order_for(product)
    2.times { register(order) }
    assert_equal 1, LightekCommerce::Subscription.count
  end
  def test_delayed_event_reads_current_processor_state_and_revokes_bank_entitlement
    order = order_for(product)
    subscription = register(order)
    bank = DymondBank::Subscription.create!(subscriber: @operator, status: "active", current_period_end: 1.month.from_now)
    subscription.update!(bank_subscription: bank)
    event = OpenStruct.new(type: "customer.subscription.updated", data: OpenStruct.new(object: {"id" => "sub_1", "status" => "active"}))
    Stripe::Subscription.stub(:retrieve, remote_subscription(order, status: "canceled")) { LightekCommerce::SubscriptionEvents.process!(event) }
    assert_equal "canceled", subscription.reload.status
    assert_equal "canceled", bank.reload.status
  end
  def test_repeated_paid_invoice_records_one_receipt
    order = order_for(product)
    register(order)
    invoice = {"id" => "in_1", "subscription" => "sub_1", "status" => "paid", "currency" => "usd", "amount_paid" => 2500}
    event = OpenStruct.new(type: "invoice.paid", created: Time.current.to_i, data: OpenStruct.new(object: invoice))
    Stripe::Subscription.stub(:retrieve, remote_subscription(order)) { 2.times { LightekCommerce::SubscriptionEvents.process!(event) } }
    assert_equal 1, LightekCommerce::BillingInvoice.count
    assert_equal 2500, LightekCommerce::BillingInvoice.sole.amount_paid_cents
  end
  def test_agency_sees_own_clients_servers_and_never_operator_or_another_agency_servers
    agency = User.create!(role: "white_label")
    client = User.create!(role: "client", agency: agency)
    other = User.create!(role: "white_label")
    mine = GatekeeperNode.create!(owner: agency)
    client_server = GatekeeperNode.create!(owner: client)
    operator_server = GatekeeperNode.create!(owner: @operator)
    foreign = GatekeeperNode.create!(owner: other)
    access = Gatekeeper::Hosting::Access
    assert_equal [mine.id, client_server.id].sort, access.nodes(agency).pluck(:id).sort
    assert_equal [client_server.id], access.nodes(client).pluck(:id)
    [operator_server, foreign].each { |node| assert_raises(access::Denied) { access.authorize!(agency, node) } }
  end
  def test_white_label_profiles_do_not_grant_operator_authority
    agency = User.create!(role: "white_label")
    profile = AgencyProfile.create!(user: agency, brand_name: "Agency")
    assert_equal "Agency", profile.brand_name
    refute Gatekeeper::Hosting::Access.super_admin?(agency)
    profile.accent_color = "red; } body { display:none"
    refute profile.valid?
  end
  def test_hosting_package_cannot_publish_vendor_cost_or_a_negative_margin_as_retail
    instance = product(product_type: "lightek_instance", subscription_plan_id: 1, price_cents: 1000)
    provider = ComputeProvider.create!(slug: "linode", health_status: "healthy")
    template = GatekeeperApplicationTemplate.create!(name: "Lightek", kind: "native_rails")
    package = HostingPackage.new(product: instance, compute_provider: provider, gatekeeper_application_template: template,
      region: "us-east", provider_plan: "g6-standard-1", monthly_cost_ceiling_cents: 1200, minimum_margin_cents: 500)
    refute package.valid?
    instance.update!(price_cents: 2500)
    assert package.valid?, package.errors.full_messages.join(", ")
    package.save!
    refute instance.update(price_cents: 1200)
  end
  def test_paid_renewals_become_one_fulfilled_order_without_reserving_stock
    original = order_for(product)
    subscription = register(original)
    invoice = {"id" => "in_renewal", "subscription" => "sub_1", "status" => "paid", "currency" => "usd",
      "amount_paid" => 2700, "subtotal" => 2500, "tax" => 200, "total" => 2700, "billing_reason" => "subscription_cycle"}
    event = OpenStruct.new(type: "invoice.paid", created: Time.current.to_i, data: OpenStruct.new(object: invoice))
    Stripe::Subscription.stub(:retrieve, remote_subscription(original)) { 2.times { LightekCommerce::SubscriptionEvents.process!(event) } }
    renewal = LightekCommerce::BillingInvoice.sole.settlement_order
    assert_equal "fulfilled", renewal.status
    assert_equal "stripe_invoice", renewal.payment_provider
    assert_equal 2700, renewal.total_cents
    assert_equal 200, renewal.tax_cents
    assert_equal original.items.sole.purchase_snapshot, renewal.items.sole.purchase_snapshot
    refute renewal.stock_reserved?
    assert_equal 2, LightekCommerce::Order.count
  end
  def test_credited_invoice_is_recorded_without_guessing_merchant_transfer_amount
    original = order_for(product)
    register(original)
    invoice = {"id" => "in_credit", "subscription" => "sub_1", "status" => "paid", "currency" => "usd",
      "amount_paid" => 2000, "subtotal" => 2500, "total" => 2500, "billing_reason" => "subscription_cycle"}
    event = OpenStruct.new(type: "invoice.paid", created: Time.current.to_i, data: OpenStruct.new(object: invoice))
    Stripe::Subscription.stub(:retrieve, remote_subscription(original)) { LightekCommerce::SubscriptionEvents.process!(event) }
    assert_nil LightekCommerce::BillingInvoice.sole.settlement_order
    assert_equal 1, LightekCommerce::Order.count
  end
  def test_return_fee_is_set_at_approval_and_deducted_from_the_linked_refund
    item = product(product_type: 'physical', billing_interval: 'one_time', price_cents: 800)
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.test', quantities: {item.id.to_s => 2})
    order.update!(status: 'fulfilled', paid_at: Time.current, fulfilled_at: Time.current,
      payment_provider: 'stripe', payment_reference: 'cs_return_fee')
    line = order.items.sole
    line.update!(purchase_snapshot: line.purchase_snapshot.merge('merchandise_discount_cents' => 199))
    returns = LightekCommerce::MerchandiseReturns.new(order: order, actor: @operator)
    record = returns.request!(item_id: line.id, quantity: 1, reason: 'Wrong size', request_key: SecureRandom.uuid)
    assert_equal 0, record.refund_fee_cents
    assert_equal 699, LightekCommerce::ReturnRefunds.maximum_fee_cents(order, line, record)
    %w[-1 0.99 700].each do |invalid|
      assert_raises(LightekCommerce::MerchandiseReturns::Invalid) { returns.approve!(record.id, refund_fee_cents: invalid) }
    end

    order.update!(payment_provider: 'network')
    assert_raises(LightekCommerce::MerchandiseReturns::Invalid) { returns.approve!(record.id, refund_fee_cents: 1) }
    assert_equal 'requested', record.reload.status
    order.update!(payment_provider: 'stripe')
    returns.approve!(record.id, refund_fee_cents: 125)
    assert_equal [125, 'approved'], record.reload.attributes.values_at('refund_fee_cents', 'status')
    assert_raises(LightekCommerce::MerchandiseReturns::Invalid) { returns.approve!(record.id, refund_fee_cents: 1) }
    assert_empty order.refunds

    returns.receive!(record.id, disposition: 'discarded')
    assert_equal 575, LightekCommerce::ReturnRefunds.amount_for(order, line, record.reload)
    refunds = LightekCommerce::Refunds
    assert_raises(refunds::Invalid) { refunds.issue!(order: order, amount_cents: 700, merchandise_return_id: record.id) }
    LightekCommerce::ProcessorPayment.stub(:intent!, 'pi_return_fee') do
      Stripe::Refund.stub(:create, ->(details, _) {
        assert_equal 575, details.fetch(:amount)
        OpenStruct.new(id: 're_return_fee', status: 'succeeded')
      }) do
        result = refunds.issue!(order: order, amount_cents: 575, merchandise_return_id: record.id)
        assert_equal [record.id, 575, 'succeeded'], result.attributes.values_at('merchandise_return_id', 'amount_cents', 'status')
      end
    end
    assert_equal 575, order.reload.refunded_cents
  end

  def test_received_return_refund_uses_discounted_merchandise_and_reconciles_signed_event_once
    item = product(product_type: 'physical', billing_interval: 'one_time', price_cents: 800)
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.test', quantities: {item.id.to_s => 2})
    order.update!(status: 'fulfilled', paid_at: Time.current, fulfilled_at: Time.current,
      payment_provider: 'stripe', payment_reference: 'cs_returns', total_cents: 1601)
    line = order.items.sole
    line.update!(purchase_snapshot: line.purchase_snapshot.merge('merchandise_discount_cents' => 199))
    service = LightekCommerce::MerchandiseReturns.new(order: order, actor: @operator)
    returns = 2.times.map do
      record = service.request!(item_id: line.id, quantity: 1, reason: 'Wrong size', request_key: SecureRandom.uuid)
      service.approve!(record.id)
      service.receive!(record.id, disposition: 'discarded')
      record.reload
    end
    first, second = returns
    assert_equal [700, 701], returns.map { |record| LightekCommerce::ReturnRefunds.amount_for(order, line, record) }
    refunds = LightekCommerce::Refunds
    assert_raises(refunds::Invalid) { refunds.issue!(order: order, amount_cents: 800, merchandise_return_id: first.id) }
    calls = []
    processor = lambda do |attributes, options|
      calls << [attributes, options]
      raise Stripe::StripeError, 'Transport failed after submission'
    end
    LightekCommerce::ProcessorPayment.stub(:intent!, 'pi_returns') do
      Stripe::Refund.stub(:create, processor) do
        refund = refunds.issue!(order: order, amount_cents: 700, merchandise_return_id: first.id)
        assert_equal [first.id, 'pending', nil], [refund.merchandise_return_id, refund.status, refund.processor_ref]
        assert_equal refund.id, refunds.issue!(order: order, amount_cents: 700, merchandise_return_id: first.id).id
        assert_raises(refunds::Invalid) { refunds.issue!(order: order, amount_cents: 701, merchandise_return_id: second.id) }
      end
    end
    assert_equal 1, calls.size
    key = calls.first.last.fetch(:idempotency_key)
    assert_includes key, order.payment_namespace
    assert_equal key, calls.first.first.dig(:metadata, :lightek_return_refund)
    object = OpenStruct.new(id: 're_linked_return', status: 'succeeded', amount: 701, metadata: {lightek_return_refund: key})
    event = OpenStruct.new(type: 'refund.updated', data: OpenStruct.new(object: object))
    LightekCommerce::StripeEvents.process!(event)
    assert_equal 0, order.reload.refunded_cents
    object.amount = 700
    2.times { LightekCommerce::StripeEvents.process!(event) }
    assert_equal 700, order.reload.refunded_cents
    assert_equal ['succeeded', 're_linked_return'], order.refunds.sole.attributes.values_at('status', 'processor_ref')
  end

  def test_customer_service_refund_reuses_durable_key_without_sending_a_second_refund
    order = order_for(product)
    order.update!(status: "paid", payment_provider: "stripe_invoice", payment_reference: "in_renewal")
    key = "customer-service-refund-79"
    calls = []
    processor = lambda do |params, options|
      calls << [params.fetch(:amount), options.fetch(:idempotency_key)]
      OpenStruct.new(id: "re_refund", status: "succeeded")
    end

    LightekCommerce::ProcessorPayment.stub(:intent!, "pi_renewal") do
      Stripe::Refund.stub(:create, processor) do
        refund = LightekCommerce::Refunds.issue!(order: order, amount_cents: 700, idempotency_key: key)
        assert_equal "succeeded", refund.status
        assert_equal refund.id, LightekCommerce::Refunds.issue!(order: order, amount_cents: 700, idempotency_key: key).id
        assert_raises(LightekCommerce::Refunds::Invalid) do
          LightekCommerce::Refunds.issue!(order: order, amount_cents: 900, idempotency_key: key)
        end
      end
    end

    assert_equal [[700, key]], calls
    assert_equal 700, order.reload.refunded_cents
  end

  def test_subscription_refund_uses_invoice_payment_instead_of_checkout_payment_intent
    order = order_for(product)
    order.update!(payment_provider: "stripe", payment_reference: "cs_1")
    Stripe::Checkout::Session.stub(:retrieve, {"payment_intent" => nil, "invoice" => "in_initial"}) do
      Stripe::Invoice.stub(:retrieve, {"id" => "in_initial", "payments" => {"data" => [{"status" => "paid", "payment" => {"type" => "payment_intent", "payment_intent" => "pi_initial"}}]}}) do
        assert_equal "pi_initial", LightekCommerce::ProcessorPayment.intent!(order: order)
      end
    end
  end
  def test_legacy_invoice_payment_intent_remains_refundable
    order = order_for(product)
    order.update!(payment_provider: "stripe_invoice", payment_reference: "in_renewal")
    Stripe::Invoice.stub(:retrieve, {"id" => "in_renewal", "payment_intent" => "pi_old"}) do
      assert_equal "pi_old", LightekCommerce::ProcessorPayment.intent!(order: order)
    end
  end
  def test_multiple_invoice_payments_require_review_instead_of_refunding_the_wrong_charge
    order = order_for(product)
    order.update!(payment_provider: "stripe_invoice", payment_reference: "in_renewal")
    payment = {"status" => "paid", "payment" => {"type" => "payment_intent", "payment_intent" => "pi_old"}}
    Stripe::Invoice.stub(:retrieve, {"payments" => {"data" => [payment, payment]}}) do
      assert_raises(LightekCommerce::Refunds::Invalid) { LightekCommerce::ProcessorPayment.intent!(order: order) }
    end
  end

  def test_completed_paid_subscription_checkout_settles_once_and_binds_initial_invoice
    order = order_for(product)
    order.update!(payment_provider: "stripe", payment_reference: "cs_paid")
    session = OpenStruct.new(id: "cs_paid", metadata: LightekCommerce::PaymentIdentity.metadata(order), currency: "usd",
      mode: "subscription", payment_status: "paid", subscription: "sub_1", invoice: "in_initial",
      amount_subtotal: 2500, amount_total: 2700, total_details: OpenStruct.new(amount_tax: 200, amount_shipping: 0))
    event = OpenStruct.new(type: "checkout.session.completed", data: OpenStruct.new(object: session))
    confirmations = []
    Stripe::Subscription.stub(:retrieve, remote_subscription(order)) do
      LightekCommerce::OrderConfirmationJob.stub(:perform_later, ->(id) { confirmations << id }) do
        2.times { LightekCommerce::StripeEvents.process!(event) }
      end
    end
    assert_equal "paid", order.reload.status
    assert_equal 2700, order.total_cents
    assert_equal [order.id], confirmations
    assert_equal order.id, LightekCommerce::BillingInvoice.sole.settlement_order_id
    assert_equal 1, LightekCommerce::Subscription.count
  end
  def test_unpaid_checkout_does_not_activate_subscription_or_install_a_server
    order = order_for(product)
    order.update!(payment_provider: "stripe", payment_reference: "cs_unpaid")
    session = OpenStruct.new(id: "cs_unpaid", metadata: LightekCommerce::PaymentIdentity.metadata(order), currency: "usd", mode: "subscription", payment_status: "unpaid")
    event = OpenStruct.new(type: "checkout.session.completed", data: OpenStruct.new(object: session))
    LightekCommerce::StripeEvents.process!(event)
    assert_equal "pending_payment", order.reload.status
    assert_equal 0, LightekCommerce::Subscription.count
  end
  def test_multiple_paid_hosting_plans_add_allowances_and_agency_includes_client_entitlements
    agency = User.create!(role: "white_label")
    client = User.create!(role: "client", agency: agency)
    plan = DymondBank::SubscriptionPlan.create!(name: "Hosting")
    SubscriptionInfrastructureEntitlement.create!(subscription_plan_id: plan.id, max_sites: 3)
    [agency, client].each do |user|
      DymondBank::Subscription.create!(subscriber: user, plan_id: plan.id, status: "active", current_period_start: 1.day.ago, current_period_end: 1.month.from_now)
    end
    DymondBank::Subscription.create!(subscriber: agency, plan_id: plan.id, status: "past_due", current_period_start: 1.day.ago, current_period_end: 1.month.from_now)
    assert_equal 6, Gatekeeper::Hosting::Access.site_limit(agency)
    assert_equal 3, Gatekeeper::Hosting::Access.site_limit(client)
  end
  def test_live_regional_cost_is_rechecked_and_cannot_erase_retail_margin
    provider = ComputeProvider.create!(slug: "linode", health_status: "healthy")
    plan = DymondBank::SubscriptionPlan.create!(name: "Hosting")
    SubscriptionInfrastructureEntitlement.create!(subscription_plan_id: plan.id, max_sites: 2)
    template = GatekeeperApplicationTemplate.create!(name: "Lightek", kind: "native_rails")
    snapshot = {"compute_provider_id" => provider.id, "region" => "us-east", "plan" => "standard",
      "template_id" => template.id, "subscription_plan_id" => plan.id, "monthly_cost_ceiling_cents" => 1200, "minimum_margin_cents" => 500}
    catalog = {"plans" => [{"id" => "standard", "monthly_cents" => 1200}], "regions" => [{"id" => "us-east"}], "images" => [{"id" => "linode/ubuntu24.04"}]}
    Gatekeeper::Compute::LinodeCatalogService.stub(:call, catalog) do
      assert_equal snapshot, Gatekeeper::Hosting::PackagePurchase.validate!(snapshot: snapshot, retail_cents: 2500, actor: @operator)
      assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::PackagePurchase.validate!(snapshot: snapshot, retail_cents: 1200, actor: @operator) }
      catalog["plans"].first["monthly_cents"] = 2400
      assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::PackagePurchase.validate!(snapshot: snapshot, retail_cents: 2500, actor: @operator) }
    end
  end

  def workspace_source(cost: 1200)
    plan = DymondBank::SubscriptionPlan.create!(name: "Hosting")
    SubscriptionInfrastructureEntitlement.create!(subscription_plan: plan, max_sites: 2)
    listing = product(product_type: "lightek_instance", price_cents: 5000, subscription_plan_id: plan.id,
      package_policy: {"limits" => {"max_storage_bytes" => 1.gigabyte}})
    HostingPackage.create!(product: listing, compute_provider: ComputeProvider.create!(slug: "linode", health_status: "healthy"),
      gatekeeper_application_template: GatekeeperApplicationTemplate.create!(name: "Lightek", kind: "native_rails"),
      region: "us-east", provider_plan: "standard", monthly_cost_ceiling_cents: cost, minimum_margin_cents: 500)
  end

  def test_workspace_tiers_create_separate_hidden_offers_with_runtime_entitlements
    source = workspace_source
    plans = {"starter" => [2500, 4], "team" => [3900, 10], "business" => [7400, 10]}.map do |tier, (price, seats)|
      package = Gatekeeper::Hosting::WorkspacePlans.create!(source: source, tier: tier, actor: @operator)
      assert_equal package, Gatekeeper::Hosting::WorkspacePlans.create!(source: source, tier: tier, actor: @operator)
      assert_equal price, package.product.price_cents
      refute package.active?
      refute package.product.published?
      assert_raises(LightekCommerce::OrderPlacement::Invalid) { order_for(package.product) }
      policy = LightekAgency::PackagePolicy.for_product(package.product)
      assert_equal({"max_sites" => 1, "max_users" => seats, "max_storage_bytes" => 1.gigabyte}, policy.fetch("limits"))
      %w[website mail messaging rooms].each { |feature| assert policy.dig("features", feature, "enabled") }
      assert policy.dig("features", "people", "enabled")
      %w[directory commerce accounting].each { |feature| assert_equal tier == "business", policy.dig("features", feature, "enabled") }
      plan = Gatekeeper::Hosting::WorkspacePlans.subscription_plan(package.product)
      assert_equal price, plan.price_monthly_cents
      refute plan.active?
      assert_equal 1, SubscriptionInfrastructureEntitlement.find_by!(subscription_plan: plan).max_sites
      plan.id
    end
    assert_equal 3, plans.uniq.size
  end

  def test_workspace_price_floor_and_published_checkout_snapshot
    source = workspace_source(cost: 2600)
    package = Gatekeeper::Hosting::WorkspacePlans.create!(source: source, tier: "starter", actor: @operator)
    expected_price = LightekCommerce::MerchantPayouts.minimum_charge_cents(3100)
    assert_equal expected_price, package.product.price_cents
    catalog = {"plans" => [{"id" => "standard", "monthly_cents" => 2700}], "regions" => [{"id" => "us-east"}],
      "images" => [{"id" => "linode/ubuntu24.04"}]}
    Gatekeeper::Compute::LinodeCatalogService.stub(:call, catalog) do
      assert_raises(Gatekeeper::Hosting::Access::Denied) do
        Gatekeeper::Hosting::WorkspacePlans.toggle!(package: package, actor: @operator)
      end
      refute package.reload.active?
      refute package.product.published?
      catalog["plans"].first["monthly_cents"] = 2600

      Gatekeeper::Hosting::WorkspacePlans.toggle!(package: package, actor: @operator)
      assert package.reload.active?
      assert package.product.published?
      assert Gatekeeper::Hosting::WorkspacePlans.subscription_plan(package.product).active?
      order = order_for(package.product)
      assert_equal expected_price, order.total_cents
      assert_equal package.id, order.items.sole.purchase_snapshot.dig("hosting", "package_id")
      assert_equal 3, order.items.sole.purchase_snapshot.dig("managed_package", "policy", "limits", "max_users")

      Gatekeeper::Hosting::RetailPricing.update!(package: package, actor: @operator, price_cents: expected_price + 200)
      assert_equal expected_price + 200, Gatekeeper::Hosting::WorkspacePlans.subscription_plan(package.product).price_monthly_cents
      assert_equal expected_price, order.reload.total_cents
      assert_equal expected_price + 200, order_for(package.product).total_cents
    end
    Gatekeeper::Hosting::WorkspacePlans.toggle!(package: package, actor: @operator)
    refute package.reload.active?
    refute package.product.published?
    refute Gatekeeper::Hosting::WorkspacePlans.subscription_plan(package.product).active?
    assert_raises(LightekCommerce::OrderPlacement::Invalid) { order_for(package.product) }
  end

  def test_workspace_seat_choice_sets_one_monthly_line_and_freezes_the_entitlement
    source = workspace_source
    expected = {
      "starter" => {3 => 2500, 4 => 3200},
      "team" => {5 => 3900, 10 => 7400},
      "business" => {10 => 7400, 11 => 8100, 101 => 71_100}
    }
    expected.each do |tier, totals|
      package = Gatekeeper::Hosting::WorkspacePlans.create!(source: source, tier: tier, actor: @operator)
      Gatekeeper::Hosting::PackagePurchase.stub(:validate!, true) do
        Gatekeeper::Hosting::WorkspacePlans.toggle!(package: package, actor: @operator)
      end
      quantities = {package.product_id.to_s => 1}
      totals.each do |seats, price|
        order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: "buyer@example.com",
          quantities: quantities, workspace_seats: seats)
        line = order.items.sole
        assert_equal 1, line.quantity
        assert_equal price, line.unit_price_cents
        assert_equal price, order.total_cents
        assert_equal seats, line.purchase_snapshot.fetch("workspace_seats")
        assert_equal seats, line.purchase_snapshot.dig("managed_package", "policy", "limits", "max_users")
        if seats == totals.keys.max
          Gatekeeper::Hosting::PackagePurchase.stub(:validate!, true) do
            Stripe::Checkout::Session.stub(:create, ->(params, _) {
              assert_equal "subscription", params[:mode]
              assert_equal 1, params[:line_items].sole[:quantity]
              assert_equal price, params[:line_items].sole.dig(:price_data, :unit_amount)
              OpenStruct.new(id: "cs_workspace_#{seats}")
            }) do
              LightekCommerce::StripeCheckout.start!(order: order, success_url: "https://shop.example.com/ok",
                cancel_url: "https://shop.example.com/cancel")
            end
          end
        end
      end
      assert_equal totals.keys.min, order_for(package.product).items.sole.purchase_snapshot.fetch("workspace_seats")
      range = Gatekeeper::Hosting::WorkspacePlans.seats_for(package.product)
      upper_limit = Gatekeeper::Hosting::WorkspacePlans.checkout_seat_limit(starting_price: package.product.price_cents, seat_range: range)
      [totals.keys.min - 1, upper_limit + 1].each do |seats|
        assert_raises(LightekCommerce::OrderPlacement::Invalid) do
          LightekCommerce::OrderPlacement.call(site: @site, customer_email: "buyer@example.com",
            quantities: quantities, workspace_seats: seats)
        end
      end
    end
    unrelated = product
    assert_raises(LightekCommerce::OrderPlacement::Invalid) do
      LightekCommerce::OrderPlacement.call(site: @site, customer_email: "buyer@example.com",
        quantities: {unrelated.id.to_s => 1}, workspace_seats: 1)
    end
  end

  def test_workspace_creation_checks_storefront_authority_and_rejects_unrelated_slug
    source = workspace_source
    customer = User.create!(role: "client")
    other_operator = User.create!(role: "super_admin")
    [customer, other_operator].each do |actor|
      assert_raises(Gatekeeper::Hosting::Access::Denied) do
        Gatekeeper::Hosting::WorkspacePlans.create!(source: source, tier: "team", actor: actor)
      end
    end
    product(slug: "lightek-workspace-team")
    assert_raises(Gatekeeper::Hosting::Access::Denied) do
      Gatekeeper::Hosting::WorkspacePlans.create!(source: source, tier: "team", actor: @operator)
    end
  end

  def nested_sale
    agency = User.create!(role: "white_label", agency: @operator, upstream_share_bps: 200)
    subagency = User.create!(role: "white_label", agency: agency, upstream_share_bps: 300)
    merchant = User.create!(role: "client", agency: subagency, upstream_share_bps: 500)
    store = DymondSite::Site.create!(tenant: merchant, host: "nested.example.com")
    item = product(site: store, price_cents: 10_000)
    order = LightekCommerce::OrderPlacement.call(site: store, customer_email: "buyer@example.com", quantities: {item.id.to_s => 1})
    [order, agency, subagency, merchant]
  end
  def test_reseller_accounts_can_nest_without_exposing_siblings_or_forming_cycles
    order, agency, subagency, merchant = nested_sale
    sibling = User.create!(role: "white_label", agency: @operator)
    assert_equal [agency.id, subagency.id, merchant.id].sort, agency.managed_account_ids.sort
    refute_includes subagency.managed_account_ids, sibling.id
    agency.agency = merchant
    refute agency.valid?
    assert_match(/descendants|cycle/, agency.errors[:agency].join)
  end
  def test_nested_upstream_sale_shares_preserve_terms_and_exclude_tax_and_shipping
    order, agency, subagency, merchant = nested_sale
    assert_equal [subagency.id, agency.id, @operator.id], order.revenue_share_snapshot.map { |row| row["beneficiary_id"] }
    assert_equal [500, 300, 200], LightekCommerce::RevenueSharing.quote(order).map { |row| row["amount_cents"] }
    subagency.update!(upstream_share_bps: 700)
    order.update!(tax_cents: 800, shipping_cents: 500, total_cents: 11_300)
    assert_equal [500, 300, 200], LightekCommerce::RevenueSharing.quote(order.reload).map { |row| row["amount_cents"] }
    quote = LightekCommerce::MerchantPayouts.fee_quote(order)
    assert_equal 1000, quote[:upstream_share_cents]
    assert_equal 10_000 - quote[:processor_reserve_cents] - 1000, quote[:net_cents]
  end
  def test_no_commission_is_earned_on_registration_or_unpaid_orders
    order, = nested_sale
    assert_equal 0, LightekCommerce::RevenueAllocation.count
    assert_raises(LightekCommerce::RevenueSharing::Invalid) { LightekCommerce::RevenueSharing.record!(order) }
    assert_equal 0, LightekCommerce::RevenueAllocation.count
  end
  def test_paid_sale_creates_one_allocation_per_ancestor_and_retains_platform_share
    order, = nested_sale
    order.update!(status: "fulfilled", paid_at: Time.current)
    2.times { LightekCommerce::RevenueSharing.record!(order) }
    assert_equal 3, order.revenue_allocations.count
    platform = order.revenue_allocations.find_by!(beneficiary: @operator)
    old = ENV["LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED"]
    ENV["LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED"] = "true"
    LightekCommerce::RevenueSharing.pay!(platform)
    assert_equal "retained", platform.reload.status
    assert_equal 200, platform.amount_cents
  ensure
    old ? ENV["LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED"] = old : ENV.delete("LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED")
  end
  def test_ancestor_connect_transfer_is_idempotent_and_deducted_from_merchant_proceeds
    order, _, subagency, = nested_sale
    order.update!(status: "fulfilled", paid_at: Time.current)
    LightekCommerce::RevenueSharing.record!(order)
    subagency.update!(stripe_connect_account_id: "acct_subagency")
    allocation = order.revenue_allocations.find_by!(beneficiary: subagency)
    calls = []
    old = ENV["LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED"]
    ENV["LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED"] = "true"
    DymondBank::StripeService.stub(:create_transfer, ->(**args) { calls << args; OpenStruct.new(id: "tr_share") }) do
      2.times { LightekCommerce::RevenueSharing.pay!(allocation) }
    end
    assert_equal 1, calls.size
    assert_equal 500, calls.sole[:amount_cents]
    assert_equal "acct_subagency", calls.sole[:destination_account]
    assert_equal "tr_share", allocation.reload.transfer_reference
    assert calls.sole[:idempotency_key].include?("upstream-#{subagency.id}")
  ensure
    old ? ENV["LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED"] = old : ENV.delete("LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED")
  end
  def test_refunds_reverse_upstream_transfers_once_per_refund_in_order
    order, _, subagency, = nested_sale
    order.update!(status: "fulfilled", paid_at: Time.current)
    LightekCommerce::RevenueSharing.record!(order)
    allocation = order.revenue_allocations.find_by!(beneficiary: subagency)
    allocation.update!(status: "transferred", transfer_reference: "tr_share")
    first = order.refunds.create!(status: "succeeded", amount_cents: 2500)
    order.update!(refunded_cents: 2500, status: "partially_refunded")
    calls = []
    Stripe::Transfer.stub(:create_reversal, ->(reference, values, options) { calls << [reference, values, options] }) do
      2.times { LightekCommerce::RevenueSharing.reverse_for_refunds!(order) }
      order.refunds.create!(status: "succeeded", amount_cents: 7500)
      order.update!(refunded_cents: 10_000, status: "refunded")
      2.times { LightekCommerce::RevenueSharing.reverse_for_refunds!(order) }
    end
    assert_equal [125, 375], calls.map { |call| call[1][:amount] }
    assert_equal 500, allocation.reload.reversed_cents
    assert calls.first[2][:idempotency_key].include?("refund-#{first.id}")
  end
  def test_overallocated_upstream_contract_is_rejected_before_payment
    agency = User.create!(role: "white_label", agency: @operator, upstream_share_bps: 6000)
    merchant = User.create!(role: "client", agency: agency, upstream_share_bps: 6000)
    store = DymondSite::Site.create!(tenant: merchant, host: "oversubscribed.example.com")
    item = product(site: store, price_cents: 10_000)
    assert_raises(LightekCommerce::OrderPlacement::Invalid) do
      LightekCommerce::OrderPlacement.call(site: store, customer_email: "buyer@example.com", quantities: {item.id.to_s => 1})
    end
    assert_equal 0, LightekCommerce::Order.count
  end

  def shipping_party
    {"name" => "Business Owner", "phone" => "2125550100", "street" => "100 Main Street", "city" => "New York", "state" => "NY", "postal_code" => "10001", "country" => "US"}
  end
  def shipping_package = {"weight_lb" => "1.5", "length_in" => "10", "width_in" => "8", "height_in" => "4"}
  def shipping_quote(**attributes)
    payload = LightekShipping::Payload.shipment!(origin: shipping_party, recipient: shipping_party, packages: [shipping_package])
    LightekShipping::Quote.create!({site: @site, service_code: "FEDEX_GROUND", service_name: "FedEx Ground", carrier_cost_cents: 900,
      platform_price_cents: 1200, customer_price_cents: 1400, expires_at: 30.minutes.from_now, shipment_payload: payload}.merge(attributes))
  end
  def test_ups_negotiated_rates_add_exactly_two_dollars_for_every_store
    account = LightekShipping::Account.create!(provider: 'ups', credential_slug: 'ups-fixture', enabled: true,
      markup_bps: 1000, fixed_markup_cents: 500)
    carrier = LightekShipping::Ups.new(account: account)
    negotiated = {'Service' => {'Code' => '03'}, 'NegotiatedRateCharges' => {'TotalCharge' => {'CurrencyCode' => 'USD', 'MonetaryValue' => '12.35'}}}
    list_only = {'Service' => {'Code' => '02'}, 'TotalCharges' => {'CurrencyCode' => 'USD', 'MonetaryValue' => '25.00'}}
    LightekShipping::Ups.stub(:new, carrier) do
      carrier.stub(:request, ->(method, path, input) {
        assert_equal [:post, '/api/rating/v2409/Shop'], [method, path]
        shipment = input.dig('RateRequest', 'Shipment')
        assert shipment.fetch('ShipmentRatingOptions').key?('NegotiatedRatesIndicator')
        assert_equal '02', shipment.dig('Package', 0, 'PackagingType', 'Code')
        {'RateResponse' => {'RatedShipment' => [negotiated, list_only]}}
      }) do
        rates = LightekShipping::Quotes.create!(site: @site, origin: shipping_party, recipient: shipping_party,
          packages: [shipping_package], customer_markup_bps: 2000, gateway: false)
        quote = rates.sole
        assert_equal ['ups', 1235, 1435, 1435], [quote.provider, quote.carrier_cost_cents, quote.platform_price_cents, quote.customer_price_cents]
        assert_equal 'ups', quote.public_attributes[:provider]
        refute quote.public_attributes.key?(:carrier_cost_cents)
      end
    end
  end

  def test_ups_labels_track_and_void_through_the_selected_carrier
    quote = shipping_quote(provider: 'ups', service_code: '03')
    order = order_for(product)
    order.update!(status: 'paid', paid_at: Time.current, purpose: 'shipping_label')
    quote.update!(purchase_order: order)
    account = LightekShipping::Account.create!(provider: 'ups', credential_slug: 'ups-fixture', enabled: true)
    carrier = LightekShipping::Ups.new(account: account)
    tracking = '1Z1234567890123456'
    handler = ->(method, path, payload = nil, **_) {
      case method
      when :post
        assert_equal '/api/shipments/v2409/ship', path
        assert_equal '03', payload.dig('ShipmentRequest', 'Shipment', 'Service', 'Code')
        assert_equal 'GIF', payload.dig('ShipmentRequest', 'LabelSpecification', 'LabelImageFormat', 'Code')
        {'ShipmentResponse' => {'ShipmentResults' => {'ShipmentIdentificationNumber' => tracking,
          'NegotiatedRateCharges' => {'TotalCharge' => {'MonetaryValue' => '9.00', 'CurrencyCode' => 'USD'}},
          'PackageResults' => {'ShippingLabel' => {'GraphicImage' => Base64.strict_encode64('GIF89a fixture')}}}}}
      when :get
        assert_equal "/api/track/v1/details/#{tracking}", path
        {'trackResponse' => {'shipment' => [{'package' => [{'currentStatus' => {'description' => 'In transit'}}]}]}}
      when :delete
        assert_equal "/api/shipments/v2409/void/cancel/#{tracking}", path
        {'VoidShipmentResponse' => {'SummaryResult' => {'Status' => {'Code' => '1'}}}}
      end
    }
    DymondBank::StripeCredentials.stub(:secret_key, 'sk_test_fake') do
      LightekShipping::Ups.stub(:new, carrier) do
        carrier.stub(:request, handler) do
          label = LightekShipping::Labels.issue!(quote: quote)
          assert_equal [tracking, 900, 'image/gif'], [label.tracking_number, label.actual_carrier_cost_cents, label.labels.first[:content_type]]
          assert_equal "https://www.ups.com/track?tracknum=#{tracking}", quote.carrier_tracking_url(tracking)
          assert_nil quote.carrier_tracking_url('https://untrusted.example')
          assert_equal 'In transit', LightekShipping::Labels.refresh!(quote: quote).carrier_status
          assert_equal 'canceled', LightekShipping::Labels.cancel!(quote: quote).status
        end
      end
    end
  end

  def test_ups_pickup_price_uses_the_negotiated_pickup_charge_plus_two_dollars
    quote = shipping_quote(provider: 'ups', service_code: '03')
    account = LightekShipping::Account.create!(provider: 'ups', credential_slug: 'ups-fixture', enabled: true)
    carrier = LightekShipping::Ups.new(account: account)
    pickup = {date: Date.current.next_day.iso8601, ready: '09:00', close: '17:00'}
    LightekShipping::Ups.stub(:new, carrier) do
      carrier.stub(:request, ->(method, path, input) {
        assert_equal [:post, '/api/shipments/v2409/pickup/oncall'], [method, path]
        assert_equal '03', input.dig('PickupRateRequest', 'ServiceDateOption')
        assert_equal '0900', input.dig('PickupRateRequest', 'PickupDateInfo', 'ReadyTime')
        {'PickupRateResponse' => {'Response' => {'ResponseStatus' => {'Code' => '1'}},
          'RateResult' => {'CurrencyCode' => 'USD', 'PreTaxTotalCharge' => '8.50', 'PreTaxTotalIncentedCharge' => '5.50'}}}
      }) do
        assert_equal 750, LightekShipping::PickupQuote.rate!(quote: quote, attributes: pickup)
        assert_raises(ArgumentError) { LightekShipping::PickupQuote.rate!(quote: quote, attributes: pickup.merge(close: '08:00')) }
      end
    end
  end

  def test_inventory_template_updates_simple_and_variant_stock_in_one_indivisible_batch
    simple = product(name: 'Simple count', track_inventory: true, inventory_quantity: 3)
    variable = product(name: 'Variant count', track_inventory: false)
    variant = variable.variants.create!(name: 'Large', price_cents: 350, inventory_quantity: 6, active: true)
    service = LightekCommerce::InventoryAdjustment
    report = LightekCommerce::InventoryReport.new(site: @site, filters: {stock: 'all'})
    template = CSV.parse(report.adjustment_csv, headers: true)
    template.each { |row| row['new_available_quantity'] = row['variant_id'] ? '0' : '9' }

    assert_raises(service::Invalid) { service.apply!(site: @site, actor: @operator, data: template.to_csv, reason: 'other') }
    assert_equal [3, 6], [simple.reload.inventory_quantity, variant.reload.inventory_quantity]
    assert_empty LightekCommerce::InventoryChange.for_site(@site)

    assert_equal 2, service.apply!(site: @site, actor: @operator, data: template.to_csv, reason: 'count')
    assert_equal [9, 0], [simple.reload.inventory_quantity, variant.reload.inventory_quantity]
    recorded = LightekCommerce::InventoryChange.for_site(@site).order(:product_id).to_a
    assert_equal [[simple.id, nil, 3, 9], [variable.id, variant.id, 6, 0]],
      recorded.map { |entry| [entry.product_id, entry.variant_id, entry.before_quantity, entry.after_quantity] }
    assert_equal [@operator.id], recorded.map(&:actor_id).uniq
    assert_equal ['Simple count', 'Variant count'], recorded.map(&:product_name)
    assert_equal [nil, 'Large'], recorded.map(&:variant_name)
    assert_equal 1, recorded.map(&:batch_key).uniq.size
    assert_equal ['csv_import'], recorded.map(&:source).uniq
    assert_equal ['count'], recorded.map(&:reason).uniq
    assert_equal ['Stock count'], recorded.map(&:reason_label).uniq
    assert_raises(ActiveRecord::ReadOnlyRecord) { recorded.first.update!(after_quantity: 12) }
    assert_raises(service::Invalid) { service.apply!(site: @site, actor: @operator, data: template.to_csv) }

    template = CSV.parse(report.adjustment_csv, headers: true)
    template.each { |row| row['new_available_quantity'] = '14' }
    simple.update!(inventory_quantity: 8)
    assert_raises(service::Invalid) { service.apply!(site: @site, actor: @operator, data: template.to_csv) }
    assert_equal [8, 0], [simple.reload.inventory_quantity, variant.reload.inventory_quantity]

    foreign = DymondSite::Site.create!(tenant: @operator, host: 'stock-write-other.test')
    assert_raises(service::Invalid) { service.apply!(site: foreign, actor: @operator, data: template.to_csv) }
    assert_empty LightekCommerce::InventoryChange.for_site(foreign)
    assert_equal 2, LightekCommerce::InventoryChange.for_site(@site).count
  end

  def test_checkout_reserves_and_releases_inventory_with_one_history_entry_per_change
    item = product(product_type: 'physical', billing_interval: 'one_time', track_inventory: true, inventory_quantity: 5)
    parent = product(product_type: 'physical', billing_interval: 'one_time')
    variant = parent.variants.create!(name: 'Blue', price_cents: 350, inventory_quantity: 3, active: true)
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.test',
      quantities: {item.id.to_s => 2, "#{parent.id}:#{variant.id}" => 1})
    records = LightekCommerce::InventoryChange.for_site(@site).where(order_id: order.id).order(:id)
    assert_equal [3, 2], [item.reload.inventory_quantity, variant.reload.inventory_quantity]
    assert_equal [[item.id, nil, 5, 3], [parent.id, variant.id, 3, 2]],
      records.pluck(:product_id, :variant_id, :before_quantity, :after_quantity)
    assert_equal ['checkout_reserved'], records.pluck(:source).uniq
    assert_equal ['System'], records.pluck(:actor_name).uniq
    assert_equal [nil], records.pluck(:actor_id).uniq

    2.times { LightekCommerce::OrderPlacement.cancel!(order) }
    assert_equal [5, 3], [item.reload.inventory_quantity, variant.reload.inventory_quantity]
    assert_equal [[item.id, nil, 3, 5], [parent.id, variant.id, 2, 3]],
      records.where(source: 'checkout_released').pluck(:product_id, :variant_id, :before_quantity, :after_quantity)
    assert_equal 4, records.count
  end

  def test_failed_checkout_rolls_back_stock_and_inventory_history
    item = product(product_type: 'physical', billing_interval: 'one_time', track_inventory: true, inventory_quantity: 5)
    sold_out = product(product_type: 'physical', billing_interval: 'one_time', track_inventory: true, inventory_quantity: 0)
    assert_raises(LightekCommerce::OrderPlacement::Invalid) do
      LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.test',
        quantities: {item.id.to_s => 1, sold_out.id.to_s => 1})
    end
    assert_equal 5, item.reload.inventory_quantity
    assert_empty LightekCommerce::InventoryChange.for_site(@site)
  end

  def test_product_editor_records_manual_changes_and_rejects_a_stale_editor
    item = product(name: 'Tracked product', track_inventory: true, inventory_quantity: 5)
    service = LightekCommerce::InventoryAdjustment
    history = LightekCommerce::InventoryChange.for_site(@site)
    old_version = service.snapshot_version(item.updated_at)
    assert_raises(service::Invalid) do
      service.update_product!(product: item, actor: @operator, attributes: {inventory_quantity: 3}, reason: 'unknown')
    end
    assert_equal 5, item.reload.inventory_quantity
    assert_empty history
    assert service.update_product!(product: item, actor: @operator,
      attributes: {inventory_quantity: 3}, version: old_version, reason: 'damaged')
    assert_equal 3, item.reload.inventory_quantity
    entry = history.sole
    assert_equal [item.id, @operator.id, 5, 3, 'product_editor'],
      [entry.product_id, entry.actor_id, entry.before_quantity, entry.after_quantity, entry.source]
    assert_equal 'Product editor', entry.source_label
    assert_equal 'damaged', entry.reason
    assert_equal 'Damaged stock', entry.reason_label

    assert_raises(service::Invalid) do
      service.update_product!(product: item, actor: @operator, attributes: {inventory_quantity: 9}, version: old_version)
    end
    assert_equal 3, item.reload.inventory_quantity
    assert service.update_product!(product: item, actor: @operator, attributes: {name: 'Renamed product', inventory_quantity: 3})
    refute service.update_product!(product: item, actor: @operator, attributes: {inventory_quantity: -1})
    assert_equal 1, history.count
    assert_equal 'Tracked product', entry.reload.product_name
    assert service.update_product!(product: item.reload, actor: @operator, attributes: {inventory_quantity: 4})
    assert_nil history.order(:id).last.reason_label
  end

  def test_manual_stock_changes_roll_back_when_the_history_write_fails
    item = product(track_inventory: true, inventory_quantity: 5)
    history = LightekCommerce::InventoryChange
    failure = ->(**) { raise ActiveRecord::RecordInvalid.new(history.new) }
    history.stub(:create!, failure) do
      assert_raises(LightekCommerce::InventoryAdjustment::Invalid) do
        LightekCommerce::InventoryAdjustment.update_product!(product: item, actor: @operator, attributes: {inventory_quantity: 7})
      end
    end
    assert_equal 5, item.reload.inventory_quantity
    assert_empty history.for_site(@site)
  end

  def test_inventory_import_rolls_back_stock_and_history_when_an_audit_write_fails
    items = [product(track_inventory: true, inventory_quantity: 1), product(track_inventory: true, inventory_quantity: 2)]
    report = LightekCommerce::InventoryReport.new(site: @site, filters: {stock: 'all'})
    template = CSV.parse(report.adjustment_csv, headers: true)
    template.each { |row| row['new_available_quantity'] = '4' }
    history = LightekCommerce::InventoryChange
    insert = history.method(:create!)
    simulated_failure = ->(**attrs) do
      raise ActiveRecord::RecordInvalid.new(history.new) if attrs[:product_id] == items.last.id

      insert.call(**attrs)
    end
    history.stub(:create!, simulated_failure) do
      assert_raises(LightekCommerce::InventoryAdjustment::Invalid) do
        LightekCommerce::InventoryAdjustment.apply!(site: @site, actor: @operator, data: template.to_csv)
      end
    end
    assert_equal [1, 2], items.map { |item| item.reload.inventory_quantity }
    assert_empty history.for_site(@site)
  end

  def test_inventory_report_mirrors_sellable_stock_and_scopes_csv_to_the_store
    simple = product(name: 'Low stock', sku: 'A%1', inventory_quantity: 3, track_inventory: true)
    variable = product(name: 'Variants', inventory_quantity: 0, track_inventory: false)
    variant = variable.variants.create!(name: '=Special', sku: '+CSV', price_cents: 350, inventory_quantity: 0, active: true)
    variable.variants.create!(name: 'Disabled', price_cents: 350, inventory_quantity: 0, active: false)
    draft = product(name: 'Draft', inventory_quantity: 0, published: false, track_inventory: true)
    product(name: 'Untracked', inventory_quantity: 0, track_inventory: false)
    other_store = DymondSite::Site.create!(tenant: @operator, host: 'inventory-other.test')
    product(site: other_store, name: 'Foreign', inventory_quantity: 0, track_inventory: true)
    report = LightekCommerce::InventoryReport
    rows = report.new(site: @site, filters: {threshold: '3'}).rows(limit: 10)
    assert_equal [[variable.id, variant.id, 0], [simple.id, nil, 3]],
      rows.map { |row| row.values_at('product_id', 'variant_id', 'inventory_quantity') }
    drafts = report.new(site: @site, filters: {stock: 'out', include_drafts: '1'})
    assert_equal [variable.id, draft.id], drafts.rows(limit: 10).map { |row| row['product_id'] }
    assert_equal [simple.id], report.new(site: @site, filters: {lookup: 'A%1'}).rows(limit: 10).map { |row| row['product_id'] }
    assert_empty report.new(site: @site, filters: {lookup: '%no_'}).rows(limit: 10)
    row = CSV.parse(drafts.csv, headers: true).first
    assert_equal ["'=Special", "'+CSV", '0', 'Published'], row.values_at('variant_name', 'sku', 'available_quantity', 'publication')
    assert_raises(report::Invalid) { report.new(site: @site, filters: {threshold: '-1'}) }
  end

  def test_inventory_report_separates_reservations_from_paid_unfulfilled_stock
    simple = product(product_type: 'physical', billing_interval: 'one_time', track_inventory: true, inventory_quantity: 10)
    parent = product(product_type: 'physical', billing_interval: 'one_time')
    variant = parent.variants.create!(name: 'Blue', price_cents: 350, inventory_quantity: 8, active: true)
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.test',
      quantities: {simple.id.to_s => 3, "#{parent.id}:#{variant.id}" => 2})
    pending = LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.test',
      quantities: {simple.id.to_s => 1})

    foreign_site = DymondSite::Site.create!(tenant: @operator, host: 'inventory-orders-other.test')
    [[foreign_site, true, true], [@site, false, true], [@site, true, false], [@site, true, nil]].each do |site, reserved, tracked|
      unrelated = LightekCommerce::Order.create!(site: site, customer_email: 'buyer@example.test', status: 'paid',
        stock_reserved: reserved, paid_at: Time.current)
      unrelated.items.create!(product: simple, name: simple.name, quantity: 9, unit_price_cents: 100, line_total_cents: 900,
        purchase_snapshot: tracked.nil? ? {} : {'track_inventory' => tracked})
    end

    report = LightekCommerce::InventoryReport.new(site: @site, filters: {stock: 'all'})
    quantities = -> { report.rows(limit: 10).map { |row| row.values_at('product_id', 'inventory_quantity', 'reserved_quantity', 'committed_quantity') } }
    assert_equal [[simple.id, 6, 4, 0], [parent.id, 6, 2, 0]], quantities.call

    order.update!(status: 'paid', paid_at: Time.current)
    assert_equal [[simple.id, 6, 1, 3], [parent.id, 6, 0, 2]], quantities.call
    csv = CSV.parse(report.csv, headers: true)
    assert_equal %w[6 1 3], csv.first.values_at('available_quantity', 'reserved_quantity', 'committed_quantity')
    assert_equal LightekCommerce::InventoryAdjustment::COLUMNS, CSV.parse(report.adjustment_csv, headers: true).headers

    order.update!(status: 'partially_refunded')
    assert_equal [[simple.id, 6, 1, 3], [parent.id, 6, 0, 2]], quantities.call
    order.update!(fulfilled_at: Time.current)
    assert_equal [[simple.id, 6, 1, 0], [parent.id, 6, 0, 0]], quantities.call
    LightekCommerce::OrderPlacement.cancel!(pending)
    assert_equal [[parent.id, 6, 0, 0], [simple.id, 7, 0, 0]], quantities.call
  end

  def test_inventory_stock_movements_keep_unsellable_units_out_of_checkout
    item = product(product_type: 'physical', billing_interval: 'one_time', track_inventory: true, inventory_quantity: 5)
    service = LightekCommerce::InventoryStockStates
    adjustments = LightekCommerce::InventoryAdjustment
    inputs = {site: @site, actor: @operator, product_id: item.id, variant_id: nil}
    move = ->(operation, quantity) do
      service.move!(**inputs, movement: operation, quantity: quantity, version: adjustments.snapshot_version(item.reload.updated_at))
    end
    original_version = adjustments.snapshot_version(item.updated_at)
    move.call('expect', 4)
    assert_raises(service::Invalid) { service.move!(**inputs, movement: 'expect', quantity: 4, version: original_version) }
    move.call('receive', 3)
    assert_equal [8, 1], [item.reload.inventory_quantity, item.incoming_quantity]
    move.call('hold', 5)
    move.call('damage_held', 2)
    move.call('damage', 1)
    assert_equal [2, 1, 3, 3], item.reload.attributes.values_at('inventory_quantity', 'incoming_quantity', 'unavailable_quantity', 'damaged_quantity')
    assert_raises(LightekCommerce::OrderPlacement::Invalid) do
      LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.test', quantities: {item.id.to_s => 3})
    end
    assert_raises(service::Invalid) { move.call('receive', 2) }
    assert_raises(service::Invalid) { move.call('release', 0) }
    assert_raises(LightekCommerce::InventoryAdjustment::Invalid) do
      adjustments.update_product!(product: item, actor: @operator, attributes: {track_inventory: false})
    end

    report = LightekCommerce::InventoryReport.new(site: @site, filters: {stock: 'all'})
    row = CSV.parse(report.csv, headers: true).first
    assert_equal %w[2 1 3 3], row.values_at('available_quantity', 'incoming_quantity', 'unavailable_quantity', 'damaged_quantity')
    history = LightekCommerce::InventoryChange.for_site(@site).where(source: 'stock_state_adjustment').order(:id)
    assert_equal 9, history.size
    receive = history.second
    assert_equal [['incoming', 4, 1], ['available', 5, 8]],
      history.where(batch_key: receive.batch_key).pluck(:stock_state, :before_quantity, :after_quantity)
    assert_equal [@operator.id], history.pluck(:actor_id).uniq

    move.call('release', 3)
    move.call('restore', 1)
    move.call('write_off', 2)
    move.call('cancel', 1)
    assert_equal [6, 0, 0, 0], item.reload.attributes.values_at('inventory_quantity', 'incoming_quantity', 'unavailable_quantity', 'damaged_quantity')
  end

  def test_inventory_stock_movements_scope_options_and_roll_back_failed_history
    item = product
    variant = item.variants.create!(name: 'Blue', price_cents: 350, inventory_quantity: 5, active: true)
    foreign = DymondSite::Site.create!(tenant: @operator, host: 'foreign-stock-states.test')
    service = LightekCommerce::InventoryStockStates
    version = LightekCommerce::InventoryAdjustment.snapshot_version(variant.updated_at)
    inputs = {site: @site, actor: @operator, product_id: item.id, variant_id: variant.id,
      movement: 'hold', quantity: '2', version: version}
    assert_raises(ActiveRecord::RecordNotFound) { service.move!(**inputs.merge(site: foreign)) }
    assert_raises(ActiveRecord::RecordNotFound) { service.move!(**inputs.merge(product_id: product.id)) }
    entries = LightekCommerce::InventoryChange.for_site(@site)
    model = LightekCommerce::InventoryChange
    record = model.method(:record!)
    model.stub(:record!, ->(**attrs) { attrs[:stock_state] == 'unavailable' ? raise(ActiveRecord::RecordInvalid.new(model.new)) : record.call(**attrs) }) do
      assert_raises(service::Invalid) { service.move!(**inputs) }
    end
    assert_empty entries
    assert_equal [5, 0], variant.reload.attributes.values_at('inventory_quantity', 'unavailable_quantity')
    service.move!(**inputs)
    assert_equal [3, 2], variant.reload.attributes.values_at('inventory_quantity', 'unavailable_quantity')
    assert_equal [variant.id], entries.pluck(:variant_id).uniq
  end

  def test_supplier_orders_receive_partial_shipments_and_reconcile_received_cost
    simple = product(product_type: 'physical', billing_interval: 'one_time', track_inventory: true, inventory_quantity: 2)
    parent = product(product_type: 'physical', billing_interval: 'one_time')
    variant = parent.variants.create!(name: 'Small', price_cents: 500, inventory_quantity: 1, active: true)
    order = LightekCommerce::SupplierOrder.create!(site: @site, supplier: 'Example Supply')
    buyer = LightekCommerce::SupplierOrders.new(order: order, actor: @operator)
    invalid = LightekCommerce::SupplierOrders::Invalid
    assert_raises(invalid) { buyer.place! }

    buyer.save_line!(item_key: simple.id.to_s, quantity: 4, unit_cost: 125)
    buyer.save_line!(item_key: "#{parent.id}:#{variant.id}", quantity: 3, unit_cost: 210)
    assert_equal [0, 0], [simple.reload.incoming_quantity, variant.reload.incoming_quantity]
    buyer.place!
    assert_equal 'ordered', order.reload.status
    assert_equal [4, 4, 2], simple.reload.attributes.values_at('incoming_quantity', 'supplier_incoming_quantity', 'inventory_quantity')
    assert_equal [3, 3, 1], variant.reload.attributes.values_at('incoming_quantity', 'supplier_incoming_quantity', 'inventory_quantity')

    stock = LightekCommerce::InventoryStockStates
    version = LightekCommerce::InventoryAdjustment.snapshot_version(simple.updated_at)
    assert_raises(stock::Invalid) do
      stock.move!(site: @site, actor: @operator, product_id: simple.id, variant_id: nil, movement: 'receive', quantity: 1, version: version)
    end

    small_line = order.lines.find_by!(variant_id: variant.id)
    buyer.receive!(line_id: small_line.id, quantity: 2, expected_received: 0)
    assert_equal [1, 1, 3], variant.reload.attributes.values_at('incoming_quantity', 'supplier_incoming_quantity', 'inventory_quantity')
    assert_raises(invalid) { buyer.receive!(line_id: small_line.id, quantity: 1, expected_received: 0) }
    assert_raises(invalid) { buyer.receive!(line_id: small_line.id, quantity: 2, expected_received: 2) }
    buyer.receive!(line_id: small_line.id, quantity: 1, expected_received: 2)

    simple_line = order.lines.find_by!(product_id: simple.id)
    buyer.receive!(line_id: simple_line.id, quantity: 4, expected_received: 0)
    assert_equal 'received', order.reload.status
    assert_equal [0, 0, 6], simple.reload.attributes.values_at('incoming_quantity', 'supplier_incoming_quantity', 'inventory_quantity')
    buyer.reconcile_invoice!(reference: 'INV-193', subtotal: 1200)
    assert_equal [1130, 1200, 'INV-193'], [order.received_subtotal_cents, order.reload.invoice_subtotal_cents, order.invoice_reference]

    movements = LightekCommerce::InventoryChange.for_site(@site).where(supplier_order_id: order.id)
    assert_equal 8, movements.count
    assert_equal %w[available incoming], movements.distinct.order(:stock_state).pluck(:stock_state)
  end

  def test_supplier_order_cancellation_preserves_manual_incoming_and_received_units
    item = product(product_type: 'physical', billing_interval: 'one_time', track_inventory: true,
      inventory_quantity: 3, incoming_quantity: 4)
    service = LightekCommerce::SupplierOrders
    order = LightekCommerce::SupplierOrder.create!(site: @site, supplier: 'Example Supply')
    buyer = service.new(order: order, actor: @operator)
    foreign = DymondSite::Site.create!(tenant: @operator, host: 'po-other.test')
    outsider = service.new(order: LightekCommerce::SupplierOrder.create!(site: foreign, supplier: 'Other Supply'), actor: @operator)
    assert_raises(service::Invalid) { outsider.save_line!(item_key: item.id.to_s, quantity: 5, unit_cost: 25) }
    buyer.save_line!(item_key: item.id.to_s, quantity: 5, unit_cost: 25)

    model = LightekCommerce::InventoryChange
    model.stub(:record!, ->(**) { raise ActiveRecord::RecordInvalid.new(model.new) }) do
      assert_raises(service::Invalid) { buyer.place! }
    end
    assert_equal 'draft', order.reload.status
    assert_equal [4, 0], item.reload.attributes.values_at('incoming_quantity', 'supplier_incoming_quantity')
    buyer.place!
    buyer.receive!(line_id: order.lines.sole.id, quantity: 3, expected_received: 0)
    buyer.cancel!
    assert_equal 'canceled', order.reload.status
    assert_equal [4, 0, 6], item.reload.attributes.values_at('incoming_quantity', 'supplier_incoming_quantity', 'inventory_quantity')
    assert_raises(service::Invalid) { buyer.cancel! }
    buyer.reconcile_invoice!(reference: 'INV-4', subtotal: 75)
    assert_equal order.received_subtotal_cents, order.reload.invoice_subtotal_cents
  end

  def test_merchandise_returns_approve_receive_and_restore_only_the_original_tracked_stock
    simple = product(product_type: 'physical', billing_interval: 'one_time', track_inventory: true, inventory_quantity: 8)
    parent = product(product_type: 'physical', billing_interval: 'one_time')
    variant = parent.variants.create!(name: 'Small', price_cents: 500, inventory_quantity: 5, active: true)
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.test',
      quantities: {simple.id.to_s => 4, "#{parent.id}:#{variant.id}" => 2})
    service = LightekCommerce::MerchandiseReturns
    returns = service.new(order: order, actor: @operator)
    line = order.items.find_by!(product_id: simple.id)
    request = {item_id: line.id, quantity: '2', reason: 'Wrong size', request_key: SecureRandom.uuid}
    assert_raises(service::Invalid) { returns.request!(**request) }
    order.update!(status: 'fulfilled', paid_at: Time.current, fulfilled_at: Time.current)
    record = returns.request!(**request)
    assert_equal record.id, returns.request!(**request).id
    assert_raises(service::Invalid) { returns.request!(**request.merge(quantity: '1')) }
    assert_raises(service::Invalid) { returns.request!(**request.merge(quantity: '3', request_key: SecureRandom.uuid)) }
    assert_raises(service::Invalid) { returns.receive!(record.id, disposition: 'available') }

    returns.approve!(record.id)
    model = LightekCommerce::InventoryChange
    model.stub(:record!, ->(**) { raise ActiveRecord::RecordInvalid.new(model.new) }) do
      assert_raises(service::Invalid) { returns.receive!(record.id, disposition: 'available') }
    end
    assert_equal [4, 'approved'], [simple.reload.inventory_quantity, record.reload.status]
    returns.receive!(record.id, disposition: 'available')
    assert_equal [6, 'received', 'available'], [simple.reload.inventory_quantity, record.reload.status, record.disposition]
    assert_raises(service::Invalid) { returns.receive!(record.id, disposition: 'available') }
    assert_equal 6, simple.reload.inventory_quantity

    variant_item = order.items.find_by!(variant_id: variant.id)
    returned_variant = returns.request!(item_id: variant_item.id, quantity: 2, reason: 'Damaged delivery', request_key: SecureRandom.uuid)
    returns.approve!(returned_variant.id)
    returns.receive!(returned_variant.id, disposition: 'damaged')
    assert_equal [3, 2], variant.reload.attributes.values_at('inventory_quantity', 'damaged_quantity')
    changes = model.for_site(@site).where(merchandise_return_id: [record.id, returned_variant.id]).order(:id)
    assert_equal [[record.id, 'available', nil], [returned_variant.id, 'damaged', variant.id]],
      changes.pluck(:merchandise_return_id, :stock_state, :variant_id)
  end

  def test_customer_can_request_returns_only_for_owned_fulfilled_physical_orders_at_this_store
    item = product(product_type: 'physical', billing_interval: 'one_time', track_inventory: true, inventory_quantity: 5)
    order = order_for(item)
    service = LightekCommerce::MerchandiseReturns
    buyer = @operator
    scope = {site: @site, buyer: buyer, id: order.id}
    order.update!(storefront_buyer_id: buyer.id, status: 'paid', paid_at: Time.current)
    assert_raises(ActiveRecord::RecordNotFound) { service.buyer_order!(**scope) }
    order.update!(status: 'fulfilled', fulfilled_at: Time.current)
    assert_equal order, service.buyer_order!(**scope)
    foreign_site = DymondSite::Site.create!(tenant: buyer, host: 'return-scope-other.test')
    assert_raises(ActiveRecord::RecordNotFound) { service.buyer_order!(**scope.merge(site: foreign_site)) }
    other_buyer = Struct.new(:id).new(buyer.id + 1)
    assert_raises(ActiveRecord::RecordNotFound) { service.buyer_order!(**scope.merge(buyer: other_buyer)) }

    request = {item_id: order.items.sole.id, quantity: 1, reason: 'Wrong size',
      request_key: SecureRandom.uuid, buyer_request: true}
    buyer_returns = service.new(order: order, actor: buyer)
    assert_raises(ActiveRecord::RecordNotFound) do
      buyer_returns.request!(**request.merge(item_id: order_for(item).items.sole.id))
    end
    record = buyer_returns.request!(**request)
    assert_equal [order.id, buyer.id, 'requested'], [record.order_id, record.requested_by_id, record.status]
    assert_equal record.id, buyer_returns.request!(**request).id
    assert_raises(ActiveRecord::RecordNotFound) { service.new(order: order, actor: other_buyer).request!(**request) }

    order.update!(storefront_buyer_id: nil)
    assert_raises(ActiveRecord::RecordNotFound) { buyer_returns.request!(**request) }
    digital_order = order_for(product(product_type: 'digital', billing_interval: 'one_time'))
    digital_order.update!(storefront_buyer_id: buyer.id, status: 'fulfilled', fulfilled_at: Time.current, paid_at: Time.current)
    assert_raises(ActiveRecord::RecordNotFound) { service.buyer_order!(**scope.merge(id: digital_order.id)) }
  end

  def test_returns_queue_filters_and_paginates_only_the_authorized_store_orders
    item = product(product_type: 'physical', billing_interval: 'one_time', track_inventory: false)
    order = order_for(item)
    order.update!(status: 'fulfilled', paid_at: Time.current, fulfilled_at: Time.current)
    record_type = LightekCommerce::MerchandiseReturn
    attrs = {order: order, order_item: order.items.sole, quantity: 1, reason: 'Fixture', requested_by_id: @operator.id}
    requested = record_type.create!(**attrs, request_key: SecureRandom.uuid)
    approved = record_type.create!(**attrs, request_key: SecureRandom.uuid, status: 'approved')
    rejected = record_type.create!(**attrs, request_key: SecureRandom.uuid, status: 'rejected')
    other_site = DymondSite::Site.create!(tenant: @operator, host: 'returns-queue-other.test')
    foreign = LightekCommerce::Order.create!(site: other_site, customer_email: 'other@example.test', status: 'fulfilled', paid_at: Time.current)
    foreign_item = foreign.items.create!(product: item, name: 'Foreign fixture', quantity: 1, unit_price_cents: 100, line_total_cents: 100)
    record_type.create!(**attrs.merge(order: foreign, order_item: foreign_item), request_key: SecureRandom.uuid)

    assert_equal [approved.id, requested.id], record_type.queue(site: @site, filter: 'open').map(&:id)
    assert_equal [requested.id], record_type.queue(site: @site, filter: 'open', before_id: approved.id).map(&:id)
    assert_equal [rejected.id], record_type.queue(site: @site, filter: 'closed').map(&:id)
    assert_equal [approved.id], record_type.queue(site: @site, filter: 'approved').map(&:id)
    assert_empty record_type.queue(site: @site, filter: 'received')
  end

  def test_merchandise_returns_release_rejected_quantities_and_keep_untracked_items_out_of_stock
    item = product(product_type: 'physical', billing_interval: 'one_time', track_inventory: false, inventory_quantity: 0)
    order = order_for(item)
    order.update!(status: 'refunded', fulfilled_at: Time.current, paid_at: Time.current)
    service = LightekCommerce::MerchandiseReturns
    returns = service.new(order: order, actor: @operator)
    details = {item_id: order.items.sole.id, quantity: 1, reason: 'Customer changed their mind'}
    denied = returns.request!(**details, request_key: SecureRandom.uuid)
    returns.reject!(denied.id)
    record = returns.request!(**details, request_key: SecureRandom.uuid)
    returns.approve!(record.id)
    another_order = order_for(item)
    assert_raises(ActiveRecord::RecordNotFound) { service.new(order: another_order, actor: @operator).cancel!(record.id) }
    assert_raises(service::Invalid) { returns.receive!(record.id, disposition: 'available') }
    returns.receive!(record.id, disposition: 'discarded')
    assert_equal [0, 'received', 'discarded'], [item.reload.inventory_quantity, record.reload.status, record.disposition]
    assert_empty LightekCommerce::InventoryChange.where(merchandise_return_id: record.id)
  end

  def test_bulk_packing_slips_scope_every_order_and_keep_selected_order
    physical = product(product_type: 'physical', billing_interval: 'one_time')
    digital = product(product_type: 'digital', billing_interval: 'one_time')
    paid = order_for(physical)
    paid.update!(status: 'paid', paid_at: Time.current)
    fulfilled = order_for(physical)
    fulfilled.update!(status: 'fulfilled', paid_at: Time.current)
    unshippable = order_for(digital)
    unshippable.update!(status: 'paid', paid_at: Time.current)
    foreign = DymondSite::Site.create!(tenant: @operator, host: 'shipping-other.test')
    slips = LightekCommerce::PackingSlips
    assert_equal [fulfilled.id, paid.id], slips.for(site: @site, order_ids: [fulfilled.id, paid.id, paid.id]).map { |slip| slip.order.id }
    assert slips.eligible?(paid)
    refute slips.eligible?(unshippable)
    assert_raises(ActiveRecord::RecordNotFound) { slips.for(site: foreign, order_ids: [paid.id]) }
    assert_raises(ActiveRecord::RecordNotFound) { slips.for(site: @site, order_ids: [paid.id, unshippable.id]) }
    assert_raises(slips::Invalid) { slips.for(site: @site, order_ids: []) }
    assert_raises(slips::Invalid) { slips.for(site: @site, order_ids: [0]) }
  end

  def test_order_timeline_orders_lifecycle_and_keeps_pending_refunds_distinct
    order = order_for(product)
    start = 1.day.ago
    order.update!(created_at: start, status: 'partially_refunded', paid_at: start + 1.minute,
      fulfilled_at: start + 3.minutes, confirmation_sent_at: start + 2.minutes)
    order.refunds.create!(amount_cents: 100, idempotency_key: 'timeline-success', status: 'succeeded',
      created_at: start + 4.minutes, updated_at: start + 5.minutes)
    order.refunds.create!(amount_cents: 250, idempotency_key: 'timeline-pending', status: 'pending',
      created_at: start + 6.minutes)

    events = LightekCommerce::OrderTimeline.for(order)
    assert_equal ['Order placed', 'Payment confirmed', 'Payment receipt sent', 'Order fulfilled',
      'Refund requested', 'Refund recorded as successful', 'Refund requested'], events.map(&:label)
    assert_equal [100, 100, 250], events.last(3).map(&:amount_cents)
    assert_equal [order.id], LightekCommerce::Order.receipt_eligible.pluck(:id)
    order.update!(deleted_at: Time.current)
    assert_empty LightekCommerce::Order.receipt_eligible
  end

  def test_order_report_filters_store_and_creation_dates_and_exports_safe_rows
    item = product(name: '=Sample', product_type: 'physical', billing_interval: 'one_time', price_cents: 2500)
    shipping_order = order_for(item)
    shipping_order.update!(customer_email: 'buyer@example.test', status: 'paid', paid_at: Time.current)
    removed = order_for(item)
    removed.update!(customer_email: 'buyer@example.test', status: 'paid', paid_at: Time.current, deleted_at: Time.current)
    foreign_site = DymondSite::Site.create!(tenant: @operator, host: 'warehouse-other.test')
    foreign_product = product(site: foreign_site, product_type: 'physical', billing_interval: 'one_time')
    LightekCommerce::OrderPlacement.call(site: foreign_site, customer_email: 'buyer@example.test',
      quantities: {foreign_product.id.to_s => 1}).update!(status: 'paid', paid_at: Time.current)
    report = LightekCommerce::OrderReport
    Time.use_zone('Eastern Time (US & Canada)') do
      filters = {lookup: 'BUYER@example.test', from: Date.current.iso8601, through: Date.current.iso8601, status: 'paid'}
      scoped = report.new(site: @site, filters: filters)
      assert_equal [shipping_order.id], scoped.recent.map(&:id)
      order = CSV.parse(scoped.csv('orders'), headers: true).sole
      line = CSV.parse(scoped.csv('items'), headers: true).sole
      assert_equal [shipping_order.id.to_s, '2500', 'paid'], order.values_at('order_id', 'total_cents', 'status')
      assert_equal [shipping_order.id.to_s, "'=Sample", '2500'], line.values_at('order_id', 'item_name', 'gross_line_cents')
      assert_equal [shipping_order.id], report.new(site: @site, filters: {lookup: "##{shipping_order.id}"}).recent.map(&:id)
      assert_raises(report::Invalid) { report.new(site: @site, filters: filters.merge(through: Date.yesterday.iso8601)) }
      assert_raises(report::Invalid) { scoped.csv('unsupported') }
    end
    assert shipping_order.items.sole.physical_for_fulfillment?
    shipping_order.items.sole.update!(purchase_snapshot: {'product_type' => 'digital'})
    refute shipping_order.items.sole.reload.physical_for_fulfillment?
  end

  def test_packing_supplies_catalog_requires_published_platform_stock
    item = product(product_type: 'physical', billing_interval: 'one_time', published: true)
    tenant = User.create!(role: 'white_label', email_address: 'supply-merchant@example.test')
    site = DymondSite::Site.create!(tenant: tenant, host: 'merchant-supplies.example.test')
    local = product(site: site, product_type: 'physical', billing_interval: 'one_time', published: true)
    collections = LightekCommerce::Collection
    collections.create!(site: site, name: 'Packing supplies', product_ids: [local.id], published: true)
    supplies = LightekShipping::Supplies
    assert_nil supplies.catalog_site_id
    catalog = collections.create!(site: @site, name: 'Packing supplies', product_ids: [item.id], published: true)
    assert_equal @site.id, supplies.catalog_site_id
    catalog.update!(published: false)
    assert_nil supplies.catalog_site_id
  end

  def test_shipping_rate_preserves_platform_margin_after_processing_reserve
    account = LightekShipping::Account.new(provider: "fedex", credential_slug: "carrier", markup_bps: 1000, fixed_markup_cents: 50, minimum_margin_cents: 200)
    price = account.retail_cents(1000)
    gross_with_tax = (price * 125 + 99) / 100
    processing = (gross_with_tax * 300 + 9999) / 10_000 + 30
    assert price - processing >= 1200
    assert price > 1000
  end
  def test_shipping_public_quote_never_contains_wholesale_cost_or_carrier_credentials
    quote = shipping_quote
    public_data = quote.public_attributes.stringify_keys
    assert_equal 1200, public_data["price_cents"]
    refute public_data.key?("carrier_cost_cents")
    refute public_data.key?("shipment_payload")
    refute public_data.key?("credential_slug")
  end
  def test_fedex_production_requires_explicit_production_activation
    account = LightekShipping::Account.new(provider: "fedex", credential_slug: "carrier", enabled: true, sandbox: false, production_approved: false)
    refute account.valid?
    assert_raises(LightekShipping::Fedex::Unavailable) { LightekShipping::Fedex.new(account: account) }
  end
  def test_shipping_payload_rejects_invalid_weight_and_unsupported_customs_destinations
    assert_raises(ArgumentError) { LightekShipping::Payload.package!(shipping_package.merge("weight_lb" => "-2")) }
    assert_raises(ArgumentError) { LightekShipping::Payload.shipment!(origin: shipping_party, recipient: shipping_party.merge("country" => "CA"), packages: [shipping_package]) }
    assert_raises(ArgumentError) { LightekShipping::Payload.shipment!(origin: shipping_party, recipient: shipping_party, packages: [shipping_package] * 41) }
  end
  def test_fedex_rates_use_account_prices_and_the_rate_api_singular_recipient_shape
    account = LightekShipping::Account.create!(provider: "fedex", credential_slug: "carrier", enabled: true)
    client = LightekShipping::Fedex.new(account: account)
    payload = LightekShipping::Payload.shipment!(origin: shipping_party, recipient: shipping_party, packages: [shipping_package])
    client.stub(:request, ->(method, path, body, **) {
      assert_equal :post, method
      assert_equal "/rate/v1/rates/quotes", path
      assert body["requestedShipment"].key?("recipient")
      refute body["requestedShipment"].key?("recipients")
      {"output" => {"rateReplyDetails" => [{"serviceType" => "FEDEX_GROUND", "serviceName" => "Ground",
        "ratedShipmentDetails" => [{"rateType" => "PAYOR_LIST_SHIPMENT", "currency" => "USD", "totalNetCharge" => "20.00"},
          {"rateType" => "PAYOR_ACCOUNT_SHIPMENT", "currency" => "USD", "totalNetCharge" => "10.01"}]}]}}
    }) do
      assert_equal 1001, client.rates(payload).sole["cost_cents"]
    end
  end
  def test_expired_or_changed_cart_shipping_quote_cannot_reach_payment
    item = product(product_type: "physical", billing_interval: "one_time", inventory_quantity: 5, track_inventory: true)
    quantities = {item.id.to_s => 1}
    quote = shipping_quote(cart_fingerprint: LightekShipping::Quotes.fingerprint(@site, quantities), expires_at: 1.minute.ago)
    assert_raises(LightekCommerce::OrderPlacement::Invalid) { LightekCommerce::OrderPlacement.call(site: @site, customer_email: "buyer@example.com", quantities: quantities, shipping_quote: quote) }
    quote.update!(expires_at: 30.minutes.from_now)
    assert_raises(LightekCommerce::OrderPlacement::Invalid) { LightekCommerce::OrderPlacement.call(site: @site, customer_email: "buyer@example.com", quantities: {item.id.to_s => 2}, shipping_quote: quote) }
    assert_equal 5, item.reload.inventory_quantity
    assert_equal 0, LightekCommerce::Order.count
  end
  def test_shipping_checkout_freezes_delivery_address_for_tax_and_adds_retail_shipping_only
    item = product(product_type: "physical", billing_interval: "one_time", inventory_quantity: 5, track_inventory: true)
    quantities = {item.id.to_s => 1}
    quote = shipping_quote(cart_fingerprint: LightekShipping::Quotes.fingerprint(@site, quantities))
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: "buyer@example.com", quantities: quantities, shipping_quote: quote)
    assert_equal 3900, order.total_cents
    DymondBank::StripeCredentials.stub(:secret_key, "sk_test_fake") do
      Stripe::Customer.stub(:create, ->(values, _) {
        assert_equal "10001", values[:shipping][:address][:postal_code]
        OpenStruct.new(id: "cus_delivery")
      }) do
        Stripe::Checkout::Session.stub(:create, ->(values, _) {
          assert_equal "cus_delivery", values[:customer]
          assert_equal 1400, values[:line_items].last[:price_data][:unit_amount]
          assert_equal "txcd_92010001", values[:line_items].last[:price_data][:product_data][:tax_code]
          refute values.key?(:shipping_address_collection)
          refute values.key?(:shipping_options)
          OpenStruct.new(id: "cs_shipping")
        }) { LightekCommerce::StripeCheckout.start!(order: order, success_url: "https://example.com", cancel_url: "https://example.com") }
      end
    end
  end
  def test_automatic_free_shipping_preserves_paid_address_label_and_merchant_proceeds
    item = product(product_type: 'physical', billing_interval: 'one_time', price_cents: 5000)
    quantities = {item.id.to_s => 1}
    quote = shipping_quote(cart_fingerprint: LightekShipping::Quotes.fingerprint(@site, quantities))
    promotion = LightekCommerce::ShippingPromotion
    promotion.save!(@site, {'enabled' => '1', 'minimum_cents' => '4000', 'maximum_rate_cents' => '1500'})
    verifier = ActiveSupport::MessageVerifier.new('fixture-shipping-review')
    order = nil
    promotion.stub(:verifier, verifier) do
      savings = promotion.savings(site: @site, quote: quote, subtotal: 5000, buyer_fee: {}, merchandise_discount: nil)
      assert_equal 1400, savings
      refute_equal savings, promotion.savings(site: @site, quote: quote, subtotal: 3000, buyer_fee: {}, merchandise_discount: nil)
      token = promotion.signed_review(@site, quote, savings)
      inputs = {site: @site, customer_email: @operator.email_address, quantities: quantities,
        shipping_quote: quote, storefront: true, storefront_buyer: @operator}
      assert_raises(LightekCommerce::OrderPlacement::Invalid) { LightekCommerce::OrderPlacement.call(**inputs) }
      assert_raises(LightekCommerce::OrderPlacement::Invalid) do
        LightekCommerce::OrderPlacement.call(**inputs, shipping_review_token: 'stale')
      end
      order = LightekCommerce::OrderPlacement.call(**inputs, shipping_review_token: token)
      assert_equal order.id, LightekCommerce::OrderPlacement.call(**inputs, shipping_review_token: token).id
    end
    assert_equal [5000, 0, 1400], [order.total_cents, order.shipping_cents, order.shipping_discount_amount]
    assert_raises(ArgumentError) do
      LightekShipping::Purchases.start!(quote: quote, email: @operator.email_address, return_url: 'https://example.com')
    end

    DymondBank::StripeCredentials.stub(:secret_key, 'sk_test_fake') do
      Stripe::Customer.stub(:create, ->(values, _) {
        assert_equal '10001', values.dig(:shipping, :address, :postal_code)
        OpenStruct.new(id: 'cus_delivery')
      }) do
        Stripe::Checkout::Session.stub(:create, ->(values, _) {
          assert_equal [5000], values[:line_items].map { |line| line.dig(:price_data, :unit_amount) }
          OpenStruct.new(id: 'cs_free_shipping')
        }) { LightekCommerce::StripeCheckout.start!(order: order, success_url: 'https://example.com', cancel_url: 'https://example.com') }
      end
    end

    session = OpenStruct.new(id: 'cs_free_shipping', metadata: LightekCommerce::PaymentIdentity.metadata(order),
      mode: 'payment', payment_status: 'paid', currency: 'usd', amount_subtotal: 5000, amount_total: 5000,
      total_details: OpenStruct.new(amount_tax: 0, amount_shipping: 1))
    event = OpenStruct.new(type: 'checkout.session.completed', data: OpenStruct.new(object: session))
    assert_raises(LightekCommerce::StripeEvents::Rejected) { LightekCommerce::StripeEvents.process!(event) }
    session.total_details.amount_shipping = 0
    LightekShipping::LabelJob.stub(:perform_later, ->(id) { assert_equal order.id, id }) do
      LightekCommerce::StripeEvents.process!(event)
    end
    assert_equal 'paid', order.reload.status
    assert_equal order.id, quote.reload.purchase_order_id
    assert_equal 3620, LightekCommerce::MerchantPayouts.fee_quote(order).fetch(:net_cents)
    LightekShipping::Account.create!(provider: 'fedex', credential_slug: 'carrier', enabled: true)
    carrier = Minitest::Mock.new
    carrier.expect(:ship, {'output' => {'transactionShipments' => [{
      'masterTrackingNumber' => '123456789012',
      'pieceResponses' => [{'packageDocuments' => [{'contentType' => 'LABEL',
        'encodedLabel' => Base64.strict_encode64('%PDF-1.7 fake label')}]}]
    }]}}, [Hash], reference: String)
    DymondBank::StripeCredentials.stub(:secret_key, 'sk_test_fake') do
      LightekShipping::Fedex.stub(:new, carrier) do
        assert_equal 'ready', LightekShipping::Labels.issue!(quote: quote).status
      end
    end
    carrier.verify
    assert_equal 'fulfilled', order.reload.status
  end

  def test_free_shipping_rate_cap_merchandise_combinations_and_insufficient_earnings
    promotion = LightekCommerce::ShippingPromotion
    promotion.save!(@site, {'enabled' => '1', 'minimum_cents' => '0', 'maximum_rate_cents' => '1500'})
    quote = shipping_quote
    inputs = {site: @site, quote: quote, buyer_fee: {}, merchandise_discount: nil}
    assert_equal 0, promotion.savings(**inputs, subtotal: 1220)
    assert_equal 1400, promotion.savings(**inputs, subtotal: 2000)
    assert_equal 0, promotion.savings(**inputs.merge(quote: shipping_quote(customer_price_cents: 1600)), subtotal: 5000)
    rule = LightekCommerce::Discount.new(name: 'Locked offer', combinable: false)
    merchandise = LightekCommerce::Discounts::Quote.new(entries: [[rule, 100]])
    assert_equal 0, promotion.savings(**inputs.merge(merchandise_discount: merchandise), subtotal: 5000)
    rule.combinable = true
    assert_equal 1400, promotion.savings(**inputs.merge(merchandise_discount: merchandise), subtotal: 5000)
    promotion.save!(@site, {'enabled' => '1', 'minimum_cents' => '0', 'maximum_rate_cents' => '1500', 'code' => 'ship-free'})
    assert promotion.valid_code?(@site, 'SHIP-FREE')
    assert_equal 0, promotion.savings(**inputs, subtotal: 5000)
    assert_equal 1400, promotion.savings(**inputs, subtotal: 5000, code: 'ship-free')
  end

  def test_sandbox_shipping_cannot_be_charged_using_live_stripe_keys
    order = order_for(product)
    order.update!(shipping_quote: shipping_quote)
    DymondBank::StripeCredentials.stub(:secret_key, "sk_live_fake") do
      assert_raises(LightekCommerce::StripeCheckout::Unavailable) { LightekCommerce::StripeCheckout.start!(order: order, success_url: "https://example.com", cancel_url: "https://example.com") }
    end
  end
  def test_uncertain_label_creation_is_not_repeated_and_is_visible_for_review
    quote = shipping_quote
    order = order_for(product)
    order.update!(status: "paid", paid_at: Time.current, purpose: "shipping_label")
    quote.update!(purchase_order: order)
    account = LightekShipping::Account.create!(provider: "fedex", credential_slug: "carrier", enabled: true)
    calls = 0
    carrier = Object.new
    carrier.define_singleton_method(:ship) { |*, **| calls += 1; raise LightekShipping::Fedex::Unavailable, "No confirmation" }
    DymondBank::StripeCredentials.stub(:secret_key, "sk_test_fake") do
      LightekShipping::Fedex.stub(:new, carrier) do
        assert_raises(LightekShipping::Fedex::Unavailable) { LightekShipping::Labels.issue!(quote: quote) }
        result = LightekShipping::Labels.issue!(quote: quote)
        assert_equal "review", result.status
      end
    end
    assert_equal 1, calls
  end
  def test_verified_label_creation_records_tracking_and_fulfills_the_paid_label_order
    quote = shipping_quote
    order = order_for(product)
    order.update!(status: "paid", paid_at: Time.current, purpose: "shipping_label")
    quote.update!(purchase_order: order)
    LightekShipping::Account.create!(provider: "fedex", credential_slug: "carrier", enabled: true)
    carrier = Object.new
    carrier.define_singleton_method(:ship) { |*, **| {"output" => {"transactionShipments" => [{"masterTrackingNumber" => "123456789012", "pieceResponses" => [{"trackingNumber" => "123456789012", "packageDocuments" => [{"contentType" => "LABEL", "encodedLabel" => Base64.strict_encode64("%PDF-1.7 fake label")}]}]}]}} }
    DymondBank::StripeCredentials.stub(:secret_key, "sk_test_fake") do
      LightekShipping::Fedex.stub(:new, carrier) do
        result = LightekShipping::Labels.issue!(quote: quote)
        assert_equal "ready", result.status
        assert_equal "123456789012", result.tracking_number
      end
    end
    assert_equal "fulfilled", order.reload.status
    assert_equal "123456789012", order.fulfillment_reference
  end

end
