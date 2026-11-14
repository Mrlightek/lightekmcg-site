# Actual commerce services and database transactions, with processor/provider calls
# replaced at their boundaries. Run without the private ecosystem dependencies.
gem "minitest", "~> 5.0"
require "minitest/autorun"
require "minitest/mock"
require "active_record"
require "active_support/all"
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
  create_table(:dymond_bank_subscription_plans) { |t| t.string :name }
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
  end
  create_table(:lightek_commerce_product_variants) do |t|
    t.references :product; t.string :name; t.boolean :active, default: true; t.integer :price_cents; t.integer :inventory_quantity
  end
  create_table(:lightek_commerce_orders) do |t|
    t.references :site; t.string :status, default: "pending_payment"; t.string :customer_email
    t.string :currency, default: "usd"; t.integer :total_cents, default: 0; t.integer :subtotal_cents, default: 0
    t.integer :tax_cents, default: 0; t.integer :shipping_cents, default: 0; t.integer :refunded_cents, default: 0
    t.string :merchant_transfer_ref; t.integer :merchant_transfer_amount_cents; t.boolean :stock_reserved, default: true; t.string :payment_namespace; t.string :payment_reference; t.string :payment_provider
    t.datetime :fulfilled_at; t.string :fulfillment_reference; t.string :fulfillment_note; t.datetime :paid_at; t.datetime :canceled_at; t.datetime :provisioned_at; t.string :purpose
  end
  create_table(:lightek_commerce_refunds) { |t| t.references :order; t.string :status; t.integer :amount_cents }
  create_table(:lightek_commerce_order_items) do |t|
    t.references :order; t.references :product; t.references :variant
    t.string :name; t.integer :quantity; t.integer :unit_price_cents; t.integer :line_total_cents
  end
end
source = Rails.root.join("db/migrate/20261112070000_connect_hosting_agencies_and_commerce.rb").read
source = source.sub("Migration[8.0]", "Migration[7.2]")
eval(source, TOPLEVEL_BINDING)
ConnectHostingAgenciesAndCommerce.new.migrate(:up)
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
class SubscriptionInfrastructureEntitlement < ApplicationRecord; end
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
  class Transfer
    def self.create_reversal(*) = raise("Unexpected transfer reversal")
  end
  module Checkout
    class Session
      def self.retrieve(*) = raise("Unexpected processor call")
      def self.create(*) = raise("Unexpected processor call")
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
require Rails.root.join('app/services/lightek_agency/package_policy').to_s
require Rails.root.join('app/services/lightek_agency/hosting_catalog').to_s
%w[gatekeeper_application_template agency_profile hosting_package lightek_commerce/product
  lightek_commerce/network_account lightek_commerce/network_sale lightek_commerce/order lightek_commerce/order_item lightek_commerce/subscription lightek_commerce/billing_invoice lightek_commerce/revenue_allocation lightek_shipping/account lightek_shipping/profile lightek_shipping/quote lightek_shipping/shipment].each do |path|
  require Rails.root.join("app/models/#{path}").to_s
end
%w[lightek_commerce/network_accounts lightek_commerce/network_gateway lightek_commerce/network_checkout lightek_shipping/payload lightek_shipping/fedex lightek_shipping/quotes lightek_shipping/purchases lightek_shipping/labels lightek_commerce/fulfillment gatekeeper/hosting/access lightek_commerce/payment_identity lightek_commerce/revenue_sharing lightek_commerce/merchant_payouts lightek_commerce/order_placement
  gatekeeper/compute/linode_catalog_service gatekeeper/hosting/package_purchase lightek_commerce/stripe_checkout lightek_commerce/stripe_events lightek_commerce/subscription_events lightek_commerce/refunds lightek_commerce/processor_payment].each do |path|
  require Rails.root.join("app/services/#{path}").to_s
end
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
