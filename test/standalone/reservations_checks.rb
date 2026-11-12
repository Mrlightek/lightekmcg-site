# Run with plain Ruby and ActiveRecord/sqlite3/minitest, no private engines.
# Set RESERVATIONS_DATABASE_URL to PostgreSQL to exercise real row concurrency.
require 'active_record'
require 'active_support/all'
require 'minitest/autorun'
require 'ostruct'
require 'stripe'
require 'pathname'
ROOT = Pathname.new(File.expand_path('../..', __dir__))
module Rails
  def self.root = ROOT
  def self.logger = Logger.new(File::NULL)
end
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
ActiveRecord::Base.establish_connection(ENV.fetch('RESERVATIONS_DATABASE_URL', 'sqlite3::memory:'))
ActiveRecord::Migration.verbose = false
ActiveRecord::ConnectionAdapters::TableDefinition.class_eval { alias_method :jsonb, :json } if ActiveRecord::Base.connection.adapter_name == 'SQLite'
ActiveRecord::Schema.define do
  create_table(:users, force: :cascade) { |t| t.string :email_address; t.string :first_name; t.string :role; t.string :stripe_connect_account_id; t.boolean :stripe_connect_details_submitted; t.boolean :stripe_connect_payouts_enabled }
  create_table(:dymond_site_sites, force: :cascade) { |t| t.string :name; t.string :host; t.string :tenant_type; t.integer :tenant_id; t.json :manifest, default: {} }
end
%w[20261028101500_create_lightek_commerce_products 20261028113000_create_lightek_commerce_orders 20261028160000_add_commerce_refund_tracking 20261028195000_add_commerce_fulfillment_tracking 20261028230000_add_commerce_payout_tracking 20261108190000_create_lightek_resort_reservations 20261108200000_add_reservation_federation 20261108210000_track_reservation_provider_receipts].each do |name|
  path = ROOT.join("db/migrate/#{name}.rb")
  next unless path.exist?
  source = path.read.gsub('Migration[8.0]', "Migration[#{ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]")
  eval(source, TOPLEVEL_BINDING, path.to_s)
  klass = source.match(/class (\w+) </)[1].constantize
  klass.new.migrate(:up)
end
ActiveRecord::Schema.define do
  create_table(:test_subscription_plans) { |t| t.string :slug; t.string :name; t.string :description; t.integer :price_monthly_cents; t.integer :price_annual_cents; t.string :currency; t.json :features_json }
  create_table(:lightek_commerce_product_variants) { |t| t.integer :product_id; t.boolean :active; t.integer :inventory_quantity }
  create_table(:test_providers) { |t| t.string :name }
  create_table(:test_nodes) { |t| t.integer :compute_provider_id; t.string :provider_resource_id; t.json :metadata, default: {} }
  create_table(:test_subscriptions) { |t| t.integer :plan_id; t.string :status; t.datetime :current_period_start; t.datetime :current_period_end }
  create_table(:test_requests) { |t| t.integer :gatekeeper_node_id; t.integer :subscription_id }
  create_table(:test_installations) { |t| t.integer :gatekeeper_node_id; t.integer :account_id; t.string :component; t.string :domain; t.string :adapter; t.json :deployment_config, default: {} }
  add_column :lightek_commerce_products, :product_type, :string, default: 'digital'
  add_column :lightek_commerce_products, :subscription_plan_id, :integer
  add_column :lightek_commerce_orders, :client_checkout_key, :string
  add_column :lightek_commerce_orders, :provisioned_at, :datetime
  add_column :lightek_commerce_orders, :provisioning_request_id, :integer
  add_column :lightek_commerce_order_items, :variant_id, :integer
end
ActiveRecord::Schema.define do
  create_table(:gatekeeper_application_templates) { |t| t.string :kind }
  create_table(:gatekeeper_application_launches) { |t| t.string :status }
  create_table(:compute_providers) { |t| t.string :slug }
  create_table(:dymond_bank_subscriptions) { |t| t.string :status }
end
%w[20261112070000_connect_hosting_agencies_and_commerce 20261112073000_add_nested_reseller_sale_shares 20261112080000_create_platform_shipping 20261112083000_connect_federated_commerce_settlement].each do |name|
  path = ROOT.join("db/migrate/#{name}.rb")
  source = path.read.gsub('Migration[8.0]', "Migration[#{ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]")
  eval(source, TOPLEVEL_BINDING, path.to_s)
  source.match(/class (\w+) </)[1].constantize.new.migrate(:up)
end
require ROOT.join('app/models/concerns/account_hierarchy').to_s
class User < ApplicationRecord
  belongs_to :agency, class_name: 'User', optional: true
  has_many :agency_clients, class_name: 'User', foreign_key: :agency_id
  include AccountHierarchy
  def full_name = email_address
  def stripe_connect_ready? = stripe_connect_account_id.present?
end
module DymondSite
  class Site < ApplicationRecord
    self.table_name = 'dymond_site_sites'
    belongs_to :tenant, polymorphic: true
  end
end
module LightekDesign
  module StarterLibrary
    def self.designs = {'starter_barber_clean_cut' => {}, 'starter_restaurant_ember_oak' => {}}
  end
end
module LightekSettings
  module WebsiteIdentity
    def self.sites_for(actor)
      return DymondSite::Site.where(tenant: actor).or(DymondSite::Site.where(id: LightekReservations::Peer.where(merchant: actor).select(:site_id))) if actor&.role == 'client'
      return DymondSite::Site.where(tenant_type: 'User', tenant_id: actor.managed_account_ids) if actor&.role == 'white_label'
      return DymondSite::Site.all if actor&.role == 'super_admin'
      return DymondSite::Site.where(tenant: actor) if actor&.role == 'admin'
      DymondSite::Site.none
    end
  end
end
class ApplicationJob
  class << self
    attr_accessor :enqueues
    def queue_as(*) = nil
    def retry_on(*) = nil
    def set(**) = self
    def perform_later(*args)
      self.enqueues ||= []
      enqueues << args
    end
  end
end
module LightekReservations
  class NotificationJob < ApplicationJob; end
end
module LightekCommerce
  class Product < ApplicationRecord
    self.table_name = 'lightek_commerce_products'
    belongs_to :site, class_name: 'DymondSite::Site'
    has_many :variants, class_name: 'LightekCommerce::ProductVariant'
    has_one :hosting_package
  end
  class ProductVariant < ApplicationRecord
    self.table_name = 'lightek_commerce_product_variants'
  end
  class OrderConfirmationJob < ApplicationJob; end
  class PaidInstanceProvisioningJob < ApplicationJob; end
  class FulfillmentNotificationJob < ApplicationJob; end
end
%w[hosting_package lightek_commerce/network_sale lightek_commerce/subscription lightek_commerce/billing_invoice lightek_commerce/revenue_allocation lightek_shipping/quote lightek_commerce/order lightek_commerce/order_item lightek_commerce/refund
  lightek_reservations/resource lightek_reservations/reservation lightek_reservations/blackout
  lightek_reservations/change lightek_reservations/peer lightek_reservations/intent lightek_commerce/payout_schedule].each { |file| require ROOT.join('app/models', file).to_s }
%w[lightek_commerce/revenue_sharing lightek_commerce/subscription_events lightek_commerce/processor_payment lightek_commerce/network_checkout lightek_shipping/quotes lightek_reservations/availability lightek_reservations/booking lightek_reservations/package_changes
  lightek_reservations/settlement lightek_reservations/federation/client lightek_reservations/federation/catalog lightek_reservations/federation/issuer lightek_commerce/payment_identity lightek_commerce/order_placement lightek_commerce/installation_checkout
  lightek_commerce/stripe_events lightek_commerce/merchant_payouts lightek_commerce/fulfillment].each { |file| require ROOT.join('app/services', file).to_s }
%w[lightek_commerce/reservation_expiry_job lightek_reservations/sweep_job lightek_commerce/scheduled_payouts_job].each { |file| require ROOT.join('app/jobs', file).to_s }
module DymondBank
  class SubscriptionPlan < ApplicationRecord
    self.table_name = 'test_subscription_plans'
  end
  SubscriptionPlan.create!(id: 1, slug: 'resort', name: 'Resort', currency: 'usd', features_json: [])
  module StripeService
    def self.sync_connect_status!(_) = true
    def self.create_transfer(**args)
      self.transfers ||= []
      transfers << args
      OpenStruct.new(id: "tr_#{args[:idempotency_key]}")
    end
    class << self; attr_accessor :transfers; end
  end
end
module Gatekeeper
  module Compute
    module Providers
      class LinodeAdapter
        class << self; attr_accessor :state, :calls, :events; end
        def node(id) = self.class.state.deep_dup
        def events_for(id)
          return self.class.events if self.class.events
          self.class.calls.any? { |call| call.first == :resize } && self.class.state['status'] == 'running' ? [{'id'=>1,'action'=>'linode_resize','status'=>'finished'}] : []
        end
        def resize_node(id, plan:)
          self.class.calls << [:resize, id, plan]
          self.class.state['status'] = 'resizing'
          {'after_event_id'=>0, 'target_plan'=>plan}
        end
        def start_node(id)
          self.class.calls << [:start, id]
          self.class.state['status'] = 'booting'
        end
        def shutdown_node(id)
          self.class.calls << [:shutdown, id]
          self.class.state['status'] = 'shutting_down'
        end
      end
    end
  end
  module Fleet
    class Transport
      class << self; attr_accessor :calls, :fail; end
      def self.run!(**args)
        raise 'Remote unavailable' if fail
        payload = args.fetch(:payload)
        self.calls << payload
        {'status'=>'applied', 'reference'=>payload[:reference], 'change_id'=>payload[:change_id]}
      end
    end
  end
end
class TestProvider < ApplicationRecord
  def adapter(**) = Gatekeeper::Compute::Providers::LinodeAdapter.new
end
class TestNode < ApplicationRecord
  belongs_to :compute_provider, class_name: 'TestProvider'
end
class TestSubscription < ApplicationRecord; end
class ProvisioningRequest < ApplicationRecord
  self.table_name = 'test_requests'
  belongs_to :gatekeeper_node, class_name: 'TestNode'
  belongs_to :subscription, class_name: 'TestSubscription'
end
class GatekeeperInstallation < ApplicationRecord
  self.table_name = 'test_installations'
  belongs_to :gatekeeper_node, class_name: 'TestNode'
  belongs_to :account, class_name: 'User'
end
require ROOT.join('app/jobs/lightek_reservations/package_change_job').to_s
require ROOT.join('app/jobs/lightek_reservations/expire_server_job').to_s
class ReservationsChecks < Minitest::Test
  def setup
    [LightekReservations::Intent, LightekReservations::Peer, LightekReservations::Change, LightekReservations::Reservation, LightekReservations::Blackout,
      LightekReservations::Resource, LightekCommerce::PayoutSchedule, LightekCommerce::OrderItem,
      LightekCommerce::Refund, LightekCommerce::Order, LightekCommerce::Product, DymondSite::Site, User].each(&:delete_all)
    [GatekeeperInstallation, ProvisioningRequest, TestNode, TestProvider, TestSubscription].each(&:delete_all)
    Gatekeeper::Compute::Providers::LinodeAdapter.state = {'type'=>'g6-nanode-1','status'=>'running'}
    Gatekeeper::Compute::Providers::LinodeAdapter.calls = []
    Gatekeeper::Compute::Providers::LinodeAdapter.events = nil
    Gatekeeper::Fleet::Transport.calls = []
    Gatekeeper::Fleet::Transport.fail = false
    @owner = User.create!(email_address: 'owner@example.test', role: 'super_admin', stripe_connect_account_id: 'acct_owner')
    @guest = User.create!(email_address: 'guest@example.test', role: 'client')
    @other = User.create!(email_address: 'other@example.test', role: 'admin', stripe_connect_account_id: 'acct_other')
    @site = DymondSite::Site.create!(name: 'Lightek', host: 'example.test', tenant: @owner)
    @foreign_site = DymondSite::Site.create!(name: 'Foreign', host: 'other.test', tenant: @other)
    @resource = resource
    @start = 3.days.from_now.change(hour: 12, min: 0, sec: 0)
    DymondBank::StripeService.transfers = []
    LightekCommerce::PaidInstanceProvisioningJob.enqueues = []
    ENV['LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED'] = 'true'
  end
  def resource(**attributes)
    LightekReservations::Resource.create!({site: @site, name: 'Creative consultation', kind: 'video', timezone: 'America/New_York', published: true, notice_minutes: 0}.merge(attributes))
  end
  def product(server: false, price: 5000, site: @site)
    LightekCommerce::Product.create!(site: site, name: 'Package', slug: SecureRandom.hex(6), product_type: server ? 'lightek_instance' : 'digital',
      subscription_plan_id: server ? 1 : nil, published: true, inventory_quantity: 100, price_cents: price)
  end
  def server(price: 10000, floor: 2000, **attrs)
    resource(kind: 'server', product: product(server: true, price: price), cost_floor_cents: floor,
      compute: {'region'=>'us-east','image'=>'linode/ubuntu24.04','plan'=>'g6-nanode-1','monthly_cost_cents'=>600}, **attrs)
  end
  def reserve(resource: @resource, customer: @guest, start: @start, key: SecureRandom.uuid, quantity: 1)
    LightekReservations::Booking.reserve!(customer: customer, resource: resource, starts_at: start.iso8601, checkout_key: key, quantity: quantity)
  end
  def event(order, **overrides)
    values = {id: 'cs_test', metadata: {'lightek_commerce_order_id'=>order.id.to_s,'lightek_site_id'=>order.site_id.to_s}, currency: 'usd', mode: 'payment',
      payment_status: 'paid', status: 'complete', amount_subtotal: order.subtotal_cents, amount_total: order.total_cents,
      total_details: OpenStruct.new(amount_tax: 0, amount_shipping: 0)}.merge(overrides)
    order.update!(payment_reference: 'cs_test', payment_provider: 'stripe')
    values[:total_details] = values[:total_details].to_h
    Stripe::Event.construct_from(type: 'checkout.session.completed', data: {object: values})
  end
  def active_server
    reservation = reserve(resource: server, start: 1.minute.from_now)
    reservation.order.update!(status: 'paid', paid_at: Time.current)
    reservation.update!(status: 'confirmed', starts_at: 10.days.ago, ends_at: 20.days.from_now)
    reservation
  end
  def test_free_appointment_confirms_without_payment
    booking = reserve
    assert_equal 'confirmed', booking.status
    assert_nil booking.order_id
    assert_equal 60.minutes, booking.ends_at - booking.starts_at
  end
  def test_checkout_retry_reuses_reservation
    key = SecureRandom.uuid
    first = reserve(key: key)
    assert_equal first.id, reserve(key: key).id
    assert_equal 1, LightekReservations::Reservation.count
  end
  def test_same_key_cannot_switch_resource
    key = SecureRandom.uuid
    reserve(key: key)
    assert_raises(LightekReservations::Booking::Invalid) { reserve(resource: resource, key: key) }
  end
  def test_overlapping_booking_is_blocked_and_adjacent_booking_is_allowed
    reserve
    assert_raises(LightekReservations::Availability::Invalid) { reserve(start: @start + 30.minutes) }
    assert_equal 'confirmed', reserve(start: @start + 60.minutes).status
  end
  def test_capacity_counts_concurrent_guests
    @resource.update!(capacity: 3)
    reserve(quantity: 2)
    assert_raises(LightekReservations::Availability::Invalid) { reserve(quantity: 2) }
    assert_equal 1, reserve(quantity: 1).quantity
  end
  def test_capacity_does_not_sum_disjoint_overlaps
    @resource.update!(capacity: 2, duration_minutes: 30)
    reserve
    reserve(start: @start + 30.minutes)
    @resource.update!(duration_minutes: 60)
    assert reserve
  end
  def test_buffers_are_part_of_reserved_capacity
    @resource.update!(buffer_minutes: 15)
    reserve
    assert_raises(LightekReservations::Availability::Invalid) { reserve(start: @start + 75.minutes) }
    assert reserve(start: @start + 90.minutes)
  end
  def test_blocked_time_is_unavailable
    @resource.blackouts.create!(starts_at: @start, ends_at: @start + 2.hours)
    assert_raises(LightekReservations::Availability::Invalid) { reserve }
  end
  def test_opening_hours_are_enforced
    @resource.update!(hours: {'1'=>[['09:00','17:00']]})
    sunday = Time.iso8601('2026-11-15T12:00:00-05:00')
    assert_raises(LightekReservations::Availability::Invalid) { reserve(start: sunday) }
  end
  def test_daylight_saving_gaps_and_ambiguities_require_explicit_offset
    assert_raises(LightekReservations::Availability::Invalid) { LightekReservations::Availability.parse('2027-03-14T02:30', @resource) }
    assert_raises(LightekReservations::Availability::Invalid) { LightekReservations::Availability.parse('2027-11-07T01:30', @resource) }
    a = LightekReservations::Availability.parse('2027-11-07T01:30:00-04:00', @resource)
    b = LightekReservations::Availability.parse('2027-11-07T01:30:00-05:00', @resource)
    assert_equal 3600, b - a
  end
  def test_payment_hold_waits_for_verified_webhook
    @resource.update!(product: product)
    booking = reserve
    assert_equal 'held', booking.status
    assert_equal 'pending_payment', booking.order.status
    LightekCommerce::StripeEvents.process!(event(booking.order, payment_status: 'unpaid'))
    assert_equal 'held', booking.reload.status
    LightekCommerce::StripeEvents.process!(event(booking.order))
    assert_equal 'confirmed', booking.reload.status
    assert_empty LightekCommerce::PaidInstanceProvisioningJob.enqueues
  end
  def test_bad_payment_total_cannot_confirm_booking
    @resource.update!(product: product)
    booking = reserve
    assert_raises(LightekCommerce::StripeEvents::Rejected) { LightekCommerce::StripeEvents.process!(event(booking.order, amount_subtotal: 1)) }
    assert_equal 'held', booking.reload.status
  end
  def test_signed_event_retries_do_not_duplicate_reservations
    @resource.update!(product: product)
    booking = reserve
    e = event(booking.order)
    2.times { LightekCommerce::StripeEvents.process!(e) }
    assert_equal 'confirmed', booking.reload.status
    assert_equal 1, LightekReservations::Reservation.count
  end
  def test_expired_hold_releases_only_after_order_is_canceled
    @resource.update!(product: product)
    booking = reserve
    booking.update!(hold_until: 1.hour.ago)
    LightekReservations::Booking.reconcile!(booking)
    assert_equal 'held', booking.status
    LightekCommerce::OrderPlacement.cancel!(booking.order)
    LightekReservations::Booking.reconcile!(booking)
    assert_equal 'expired', booking.status
    assert_equal 100, @resource.product.reload.inventory_quantity
  end
  def test_customer_cannot_cancel_another_customers_booking
    booking = reserve
    assert_raises(LightekReservations::Booking::Invalid) { LightekReservations::Booking.cancel!(reservation: booking, actor: @other) }
    assert_equal 'confirmed', booking.reload.status
  end
  def test_cancel_releases_capacity_without_refunding
    @resource.update!(product: product)
    booking = reserve
    booking.order.update!(status: 'paid', paid_at: Time.current)
    LightekReservations::Booking.reconcile!(booking)
    LightekReservations::Booking.cancel!(reservation: booking, actor: @guest)
    assert_equal 'canceled', booking.status
    assert_equal 'paid', booking.order.reload.status
    assert_empty booking.order.refunds
    assert reserve
  end
  def test_reschedule_excludes_its_own_capacity
    booking = reserve
    LightekReservations::Booking.reschedule!(reservation: booking, actor: @guest, starts_at: (@start + 30.minutes).iso8601)
    assert_equal @start + 30.minutes, booking.starts_at
  end
  def test_reschedule_cannot_take_another_booking
    booking = reserve
    reserve(start: @start + 2.hours)
    assert_raises(LightekReservations::Availability::Invalid) do
      LightekReservations::Booking.reschedule!(reservation: booking, actor: @guest, starts_at: (@start + 2.hours).iso8601)
    end
    assert_equal @start, booking.reload.starts_at
  end
  def test_server_preserves_industry_and_contract_snapshot
    package = server(template_key: 'starter_barber_clean_cut', accommodations: ['Private server', 'Bookings', 'Storefront'])
    booking = reserve(resource: package)
    package.update!(name: 'New price', accommodations: ['Changed'])
    assert_equal ['Private server', 'Bookings', 'Storefront'], booking.package_snapshot['accommodations']
    assert_equal 'starter_barber_clean_cut', booking.package_snapshot['template_key']
    assert_equal 10000, booking.package_snapshot['price_cents']
  end
  def test_server_price_cannot_undercut_infrastructure
    assert_raises(ActiveRecord::RecordInvalid) { server(price: 400, floor: 600) }
    assert_raises(ActiveRecord::RecordInvalid) { server(floor: 500) }
  end
  def test_cross_site_product_is_rejected
    @resource.product = product(site: @foreign_site)
    refute @resource.valid?
    assert @resource.errors[:product].any?
  end
  def test_white_label_cannot_invent_its_own_infrastructure_cost
    offer = server
    offer.site = @foreign_site
    offer.product = product(server: true, site: @foreign_site)
    refute offer.valid?
    assert offer.errors[:source_resource].any?
    approved = server
    offer.source_resource = approved
    assert offer.valid?, offer.errors.full_messages.join(', ')
    offer.compute = offer.compute.merge('monthly_cost_cents'=>1)
    refute offer.valid?
  end
  def test_upgrade_credits_original_rate_instead_of_new_retail_price
    booking = active_server
    booking.resource.product.update!(price_cents: 90000)
    now = Time.utc(2026, 11, 8, 12)
    booking.update!(starts_at: now - 10 * 86400, ends_at: now + 20 * 86400)
    change = LightekReservations::PackageChanges.quote!(reservation: booking, target: server(price: 20000), now: now)
    assert_in_delta 6667, change.amount_cents, 1
    assert_equal 10000, change.quote.dig('original','price_cents')
    refute change.quote['renewal']
  end
  def test_downgrade_prepays_next_term_without_current_term_refund
    booking = active_server
    change = LightekReservations::PackageChanges.quote!(reservation: booking, target: server(price: 5000))
    assert_equal 5000, change.amount_cents
    assert change.quote['renewal']
    assert_equal booking.ends_at.to_i, change.effective_at.to_i
    LightekReservations::PackageChanges.accept!(change: change, actor: @guest)
    assert_equal 'awaiting_payment', change.status
    assert_equal 10000, booking.reload.package_snapshot['price_cents']
  end
  def test_package_payment_never_enqueues_another_server
    booking = active_server
    change = LightekReservations::PackageChanges.quote!(reservation: booking, target: server(price: 20000))
    2.times { LightekReservations::PackageChanges.accept!(change: change, actor: @guest) }
    assert_equal 2, LightekCommerce::Order.count
    assert_equal 'reservation_change', change.order.purpose
    LightekCommerce::StripeEvents.process!(event(change.order))
    assert_equal 'scheduled', change.reload.status
    assert_empty LightekCommerce::PaidInstanceProvisioningJob.enqueues
  end
  def test_change_order_cancellation_does_not_invent_stock
    booking = active_server
    target = server(price: 20000)
    change = LightekReservations::PackageChanges.quote!(reservation: booking, target: target)
    LightekReservations::PackageChanges.accept!(change: change, actor: @guest)
    stock = target.product.inventory_quantity
    LightekCommerce::OrderPlacement.cancel!(change.order)
    assert_equal stock, target.product.reload.inventory_quantity
  end
  def test_quote_cannot_be_accepted_after_expiry
    booking = active_server
    change = LightekReservations::PackageChanges.quote!(reservation: booking, target: server(price: 20000))
    change.update!(expires_at: 1.minute.ago)
    assert_raises(LightekReservations::PackageChanges::Invalid) { LightekReservations::PackageChanges.accept!(change: change, actor: @guest) }
  end
  def test_change_cannot_cross_site
    booking = active_server
    target = server(price: 20000)
    target.update_columns(site_id: @foreign_site.id)
    assert_raises(LightekReservations::PackageChanges::Invalid) { LightekReservations::PackageChanges.quote!(reservation: booking, target: target) }
  end
  def test_two_active_changes_cannot_be_purchased
    booking = active_server
    changes = 2.times.map { LightekReservations::PackageChanges.quote!(reservation: booking, target: server(price: 20000)) }
    LightekReservations::PackageChanges.accept!(change: changes.first, actor: @guest)
    assert_raises(LightekReservations::PackageChanges::Invalid) { LightekReservations::PackageChanges.accept!(change: changes.last, actor: @guest) }
  end
  def test_payout_default_is_every_fourteen_days
    schedule = LightekCommerce::PayoutSchedule.for!(@owner)
    assert_equal 'biweekly', schedule.cadence
    assert_equal 14, schedule.interval_days
    assert_equal schedule.id, LightekCommerce::PayoutSchedule.for!(@owner).id
    schedule.update!(cadence: 'weekly')
    assert_equal 7, schedule.interval_days
  end
  def fulfilled_order(site: @site)
    order = LightekCommerce::Order.create!(site: site, customer_email: @guest.email_address, total_cents: 10000, subtotal_cents: 10000, status: 'fulfilled', paid_at: Time.current, payment_provider: 'stripe', payment_reference: 'cs_test_fulfilled')
    order
  end
  def test_automatic_release_is_idempotent
    order = fulfilled_order
    schedule = LightekCommerce::PayoutSchedule.for!(@owner)
    schedule.update!(next_run_at: 1.minute.ago)
    2.times { LightekCommerce::ScheduledPayoutsJob.new.perform }
    assert_equal 1, DymondBank::StripeService.transfers.size
    assert order.reload.merchant_transfer_ref
    assert schedule.reload.next_run_at > Time.current
  end
  def test_payout_does_not_capture_another_merchants_orders_even_for_super_admin
    foreign_order = fulfilled_order(site: @foreign_site)
    schedule = LightekCommerce::PayoutSchedule.for!(@owner)
    schedule.update!(next_run_at: 1.minute.ago)
    LightekCommerce::ScheduledPayoutsJob.new.perform
    assert_nil foreign_order.reload.merchant_transfer_ref
    assert_raises(LightekCommerce::MerchantPayouts::Invalid) { LightekCommerce::MerchantPayouts.request!(order: foreign_order, merchant: @owner) }
  end
  def test_disabled_automatic_transfers_retain_due_run_for_retry
    fulfilled_order
    schedule = LightekCommerce::PayoutSchedule.for!(@owner)
    schedule.update!(next_run_at: 1.minute.ago)
    ENV['LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED'] = 'false'
    LightekCommerce::ScheduledPayoutsJob.new.perform
    assert schedule.reload.last_error.present?
    assert schedule.next_run_at < Time.current
    assert_empty DymondBank::StripeService.transfers
  end
  def test_server_payout_reserves_platform_cost_and_margin
    booking = active_server
    quote = LightekCommerce::MerchantPayouts.fee_quote(booking.order)
    assert_equal 2000, quote[:infrastructure_reserve_cents]
    assert_equal 10000 - 330 - 2000, quote[:net_cents]
  end
  def test_pending_refund_prevents_transfer
    order = fulfilled_order
    order.refunds.create!(amount_cents: 100, status: 'pending', idempotency_key: SecureRandom.uuid)
    assert_raises(LightekCommerce::MerchantPayouts::Invalid) { LightekCommerce::MerchantPayouts.request!(order: order, merchant: @owner) }
    assert_empty DymondBank::StripeService.transfers
  end
  def attach_server(booking)
    provider = TestProvider.create!(name: 'Linode')
    node = TestNode.create!(compute_provider: provider, provider_resource_id: '123')
    subscription = TestSubscription.create!(plan_id: 1, status: 'active')
    request = ProvisioningRequest.create!(gatekeeper_node: node, subscription: subscription)
    booking.order.update!(provisioning_request_id: request.id, provisioned_at: Time.current)
    GatekeeperInstallation.create!(gatekeeper_node: node, account: @guest, component: 'lightek_app', adapter: 'native_rails', domain: 'client.example.test')
    request
  end
  def paid_change(booking, target)
    change = LightekReservations::PackageChanges.quote!(reservation: booking, target: target)
    LightekReservations::PackageChanges.accept!(change: change, actor: @guest)
    LightekCommerce::StripeEvents.process!(event(change.order))
    change.reload
  end
  def test_package_does_not_activate_until_provider_and_remote_application_confirm
    booking = active_server
    attach_server(booking)
    target = server(price: 20000, compute: {'region'=>'us-east','image'=>'linode/ubuntu24.04','plan'=>'g6-standard-1','monthly_cost_cents'=>1200})
    change = paid_change(booking, target)
    LightekReservations::PackageChangeJob.new.perform(change.id)
    assert_equal 'applying', change.reload.status
    assert_equal 10000, booking.reload.package_snapshot['price_cents']
    assert_equal 1, Gatekeeper::Compute::Providers::LinodeAdapter.calls.size
    assert_empty Gatekeeper::Fleet::Transport.calls
    Gatekeeper::Compute::Providers::LinodeAdapter.state = {'type'=>'g6-standard-1','status'=>'running'}
    2.times { LightekReservations::PackageChangeJob.new.perform(change.id) }
    assert_equal 'applied', change.reload.status
    assert_equal 20000, booking.reload.package_snapshot['price_cents']
    assert_equal 1, Gatekeeper::Fleet::Transport.calls.size
    assert_equal 'fulfilled', change.order.reload.status
  end
  def test_remote_failure_can_resume_without_another_resize_or_charge
    booking = active_server
    attach_server(booking)
    change = paid_change(booking, server(price: 20000))
    Gatekeeper::Fleet::Transport.fail = true
    assert_raises(RuntimeError) { LightekReservations::PackageChangeJob.new.perform(change.id) }
    assert_equal 'failed', change.reload.status
    assert_equal 10000, booking.reload.package_snapshot['price_cents']
    Gatekeeper::Fleet::Transport.fail = false
    change.update!(status: 'scheduled')
    LightekReservations::PackageChangeJob.new.perform(change.id)
    assert_equal 'applied', change.reload.status
    assert_empty Gatekeeper::Compute::Providers::LinodeAdapter.calls
    assert_equal 2, LightekCommerce::Order.count
  end
  def test_expired_reservation_renews_full_term_and_restarts_existing_server
    booking = active_server
    request = attach_server(booking)
    booking.update!(status: 'expired', ends_at: 4.days.ago)
    request.subscription.update!(status: 'past_due')
    change = paid_change(booking, server(price: 5000))
    assert_equal 5000, change.amount_cents
    Gatekeeper::Compute::Providers::LinodeAdapter.state['status'] = 'offline'
    LightekReservations::PackageChangeJob.new.perform(change.id)
    assert_equal [:start, '123'], Gatekeeper::Compute::Providers::LinodeAdapter.calls.last
    Gatekeeper::Compute::Providers::LinodeAdapter.state['status'] = 'running'
    LightekReservations::PackageChangeJob.new.perform(change.id)
    assert_equal 'confirmed', booking.reload.status
    assert booking.ends_at > 27.days.from_now
    assert_equal 'active', request.subscription.reload.status
  end
  def test_unpaid_term_pauses_server_after_grace_without_deleting_data
    booking = active_server
    request = attach_server(booking)
    booking.update!(ends_at: 4.days.ago)
    LightekReservations::ExpireServerJob.new.perform(booking.id)
    assert_equal [[:shutdown, '123']], Gatekeeper::Compute::Providers::LinodeAdapter.calls
    assert_equal 'confirmed', booking.reload.status
    Gatekeeper::Compute::Providers::LinodeAdapter.state['status'] = 'offline'
    LightekReservations::ExpireServerJob.new.perform(booking.id)
    assert_equal 'expired', booking.reload.status
    assert_equal 'past_due', request.subscription.reload.status
    assert_equal 1, TestNode.count
  end
  def test_small_proration_is_reserved_for_next_term_instead_of_invalid_stripe_charge
    booking = active_server
    booking.update!(ends_at: 1.minute.from_now)
    change = LightekReservations::PackageChanges.quote!(reservation: booking, target: server(price: 20000))
    assert change.quote['renewal']
    assert_equal 20000, change.amount_cents
  end

  def test_same_platform_stripe_account_uses_distinct_site_namespaces
    a = fulfilled_order
    b = fulfilled_order(site: @foreign_site)
    refute_equal a.payment_namespace, b.payment_namespace
    a_key = LightekCommerce::PaymentIdentity.key(a, 'checkout')
    b.id = a.id
    refute_equal a_key, LightekCommerce::PaymentIdentity.key(b, 'checkout')
  end
  def test_foreign_installation_webhook_is_ignored_before_order_settlement
    @resource.update!(product: product)
    booking = reserve
    e = event(booking.order)
    e.data.object.metadata['lightek_host_key'] = 'another-instance'
    assert_nil LightekCommerce::StripeEvents.process!(e)
    assert_equal 'pending_payment', booking.order.reload.status
    assert_equal 'held', booking.reload.status
  end

  def test_reported_target_plan_cannot_activate_while_resize_event_is_pending
    booking = active_server
    attach_server(booking)
    target = server(price: 20000, compute: {'region'=>'us-east','image'=>'linode/ubuntu24.04','plan'=>'g6-standard-1','monthly_cost_cents'=>1200})
    change = paid_change(booking, target)
    LightekReservations::PackageChangeJob.new.perform(change.id)
    Gatekeeper::Compute::Providers::LinodeAdapter.state = {'type'=>'g6-standard-1','status'=>'running'}
    Gatekeeper::Compute::Providers::LinodeAdapter.events = [{'id'=>1,'action'=>'linode_resize','status'=>'scheduled'}]
    LightekReservations::PackageChangeJob.new.perform(change.id)
    assert_equal 'applying', change.reload.status
    assert_equal 10000, booking.reload.package_snapshot['price_cents']
    assert_empty Gatekeeper::Fleet::Transport.calls
    Gatekeeper::Compute::Providers::LinodeAdapter.events = [{'id'=>1,'action'=>'linode_resize','status'=>'finished'}]
    LightekReservations::PackageChangeJob.new.perform(change.id)
    assert_equal 'applied', change.reload.status
  end

end
