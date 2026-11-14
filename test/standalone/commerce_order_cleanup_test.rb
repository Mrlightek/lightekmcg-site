# Run against the real commerce models and transactions, without private gems.
require_relative "commerce_hosting_test"
require Rails.root.join("db/migrate/20261114140000_add_commerce_order_deletion").to_s
AddCommerceOrderDeletion.new.migrate(:up)
LightekCommerce::Order.reset_column_information
require Rails.root.join("app/services/lightek_commerce/order_removal").to_s
require Rails.root.join("app/services/lightek_commerce/installations").to_s

class CommerceOrderCleanupTest < CommerceHostingTest
  CommerceHostingTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }

  def checkout(order, **values)
    OpenStruct.new({id: order.payment_reference, status: "open", payment_status: "unpaid", currency: order.currency,
      metadata: LightekCommerce::PaymentIdentity.metadata(order)}.merge(values))
  end

  def stripe_order
    order_for(product(billing_interval: "one_time")).tap { |order| order.update!(payment_provider: "stripe", payment_reference: "cs_cleanup") }
  end

  def test_unpaid_order_is_hidden_and_inventory_is_released_exactly_once
    merchandise = product(product_type: "physical", billing_interval: "one_time", track_inventory: true, inventory_quantity: 3)
    order = order_for(merchandise)
    assert_equal 2, merchandise.reload.inventory_quantity
    2.times { LightekCommerce::OrderRemoval.call(order) }
    assert_equal 3, merchandise.reload.inventory_quantity
    assert_equal "canceled", order.reload.status
    assert order.deleted_at?
    refute LightekCommerce::Order.visible.exists?(order.id)
    assert LightekCommerce::Order.exists?(order.id), "retain record for delayed payment webhooks"
    assert_equal 1, order.items.count
  end

  def test_canceled_order_can_be_removed_without_releasing_stock_twice
    order = order_for(product)
    LightekCommerce::OrderPlacement.cancel!(order)
    LightekCommerce::OrderRemoval.call(order)
    assert order.reload.deleted_at?
  end

  def test_paid_and_installation_records_cannot_be_deleted_even_by_direct_request
    %w[paid fulfilled partially_refunded refunded].each do |status|
      order = order_for(product)
      order.update!(status: status)
      assert_raises(LightekCommerce::OrderRemoval::Invalid) { LightekCommerce::OrderRemoval.call(order) }
      refute order.reload.deleted_at?
    end
    [:paid_at, :provisioned_at].each do |field|
      order = order_for(product)
      order.update!(field => Time.current)
      assert_raises(LightekCommerce::OrderRemoval::Invalid) { LightekCommerce::OrderRemoval.call(order) }
      assert_equal "pending_payment", order.reload.status
    end
    order = order_for(product)
    launch_id = ActiveRecord::Base.connection.insert("INSERT INTO gatekeeper_application_launches DEFAULT VALUES")
    order.update_column(:gatekeeper_application_launch_id, launch_id)
    assert_raises(LightekCommerce::OrderRemoval::Invalid) { LightekCommerce::OrderRemoval.call(order) }
  end

  def test_open_stripe_checkout_must_expire_before_order_is_hidden
    order = stripe_order
    expired = checkout(order, status: "expired")
    calls = []
    Stripe::Checkout::Session.define_singleton_method(:expire) { |*args| calls << args; expired }
    Stripe::Checkout::Session.stub(:retrieve, checkout(order)) { LightekCommerce::OrderRemoval.call(order) }
    assert_equal [["cs_cleanup", {}, {api_key: "test-key"}]], calls
    assert order.reload.deleted_at?
    assert_equal "canceled", order.status
  ensure
    Stripe::Checkout::Session.singleton_class.remove_method(:expire)
  end

  def test_paid_settling_unknown_and_unconfirmed_checkouts_stay_visible
    [{payment_status: "paid"}, {status: "complete"}, {status: "unknown"}].each do |state|
      order = stripe_order
      Stripe::Checkout::Session.stub(:retrieve, checkout(order, **state)) do
        assert_raises(LightekCommerce::OrderRemoval::Invalid) { LightekCommerce::OrderRemoval.call(order) }
      end
      assert_equal "pending_payment", order.reload.status
      refute order.deleted_at?
    end
    order = stripe_order
    Stripe::Checkout::Session.define_singleton_method(:expire) { |*_| OpenStruct.new(status: "open", payment_status: "unpaid") }
    Stripe::Checkout::Session.stub(:retrieve, checkout(order)) do
      assert_raises(LightekCommerce::OrderRemoval::Invalid) { LightekCommerce::OrderRemoval.call(order) }
    end
    refute order.reload.deleted_at?
  ensure
    Stripe::Checkout::Session.singleton_class.remove_method(:expire)
  end

  def test_processor_failure_or_mismatched_checkout_keeps_order_and_stock
    order = stripe_order
    Stripe::Checkout::Session.stub(:retrieve, ->(*_) { raise Stripe::StripeError, "offline" }) do
      assert_raises(LightekCommerce::OrderRemoval::Invalid) { LightekCommerce::OrderRemoval.call(order) }
    end
    Stripe::Checkout::Session.stub(:retrieve, checkout(order, metadata: {lightek_commerce_order_id: "other", lightek_site_id: order.site_id})) do
      assert_raises(LightekCommerce::OrderRemoval::Invalid) { LightekCommerce::OrderRemoval.call(order) }
    end
    refute order.reload.deleted_at?
    assert_equal "pending_payment", order.status
  end

  def test_expired_checkout_and_deleted_checkout_cannot_be_reopened
    order = stripe_order
    session = checkout(order, status: "expired")
    Stripe::Checkout::Session.stub(:retrieve, session) { LightekCommerce::OrderRemoval.call(order) }
    # A delayed processor expiration can still find the retained tombstone.
    event = OpenStruct.new(type: "checkout.session.expired", data: OpenStruct.new(object: session))
    assert_equal order, LightekCommerce::StripeEvents.process!(event)
    assert order.reload.deleted_at?
    assert_raises(LightekCommerce::StripeCheckout::Unavailable) do
      LightekCommerce::StripeCheckout.start!(order: order, success_url: "https://example.com", cancel_url: "https://example.com")
    end
  end

  def test_network_payment_requires_upstream_cancellation
    order = stripe_order
    order.update!(payment_provider: "network", network_reference: "remote")
    LightekCommerce::NetworkCheckout.stub(:synchronize!, order) do
      assert_raises(LightekCommerce::OrderRemoval::Invalid) { LightekCommerce::OrderRemoval.call(order) }
    end
    refute order.reload.deleted_at?
    cancel = ->(record) { LightekCommerce::OrderPlacement.cancel!(record) }
    LightekCommerce::NetworkCheckout.stub(:synchronize!, cancel) { LightekCommerce::OrderRemoval.call(order) }
    assert order.reload.deleted_at?
  end

  def test_deleted_installation_orders_leave_the_installations_list
    plan = DymondBank::SubscriptionPlan.create!(name: "Test instance")
    order = order_for(product(product_type: "lightek_instance", billing_interval: "one_time", subscription_plan_id: plan.id))
    assert_includes LightekCommerce::Installations.scope_for(@operator, operator: true), order
    LightekCommerce::OrderRemoval.call(order)
    refute_includes LightekCommerce::Installations.scope_for(@operator, operator: true), order
  end
end

# Exercise real controller actions and the rendered view with only host auth and
# engine layout replaced. Role and site authorization use production code.
require "action_controller"
require "action_dispatch/testing/integration"
module DymondDash
  class ApplicationController < ActionController::Base
    def current_user = User.find_by(id: request.headers["X-Test-User"])
    rescue_from(ActiveRecord::RecordNotFound) { head :not_found }
  end
end
module Dashboard; end
require Rails.root.join("app/controllers/dashboard/settings_home_controller").to_s
require Rails.root.join("app/controllers/dashboard/commerce_base_controller").to_s
require Rails.root.join("app/controllers/dashboard/commerce_orders_controller").to_s
require Rails.root.join("app/services/lightek_settings/website_identity").to_s
Dashboard::CommerceOrdersController.prepend_view_path(Rails.root.join("app/views"))
Dashboard::CommerceOrdersController.layout false
CLEANUP_ROUTES = ActionDispatch::Routing::RouteSet.new
CLEANUP_ROUTES.draw do
  get "/dashboard/commerce/orders", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_orders
  delete "/dashboard/commerce/orders", to: "dashboard/commerce_orders#bulk_destroy"
  delete "/dashboard/commerce/orders/:order_id", to: "dashboard/commerce_orders#destroy", as: :dashboard_commerce_order
  get "/dashboard/installations", to: "dashboard/commerce_orders#index", as: :dashboard_installations
  get "/dashboard/commerce/payouts", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_payouts
  get "/dashboard/commerce/products", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_products
end
Dashboard::CommerceOrdersController.include(CLEANUP_ROUTES.url_helpers)
Dashboard::CommerceOrdersController.helper(CLEANUP_ROUTES.url_helpers)
CLEANUP_APP = Rack::Builder.new do
  use ActionDispatch::Flash
  run CLEANUP_ROUTES
end.to_app

class CommerceOrderCleanupHttpTest < CommerceHostingTest
  CommerceHostingTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def request(method, path, actor: @operator, **params)
    @http ||= ActionDispatch::Integration::Session.new(CLEANUP_APP)
    @http.public_send(method, path, params: params, headers: {"X-Test-User" => actor&.id.to_s})
    @http.response
  end
  def test_single_delete_and_visible_list_rendering
    order = order_for(product(billing_interval: "one_time"))
    paid = order_for(product(billing_interval: "one_time"))
    paid.update!(status: "paid")
    # Render just the pending row; paid fulfillment/refund routes belong to the host.
    paid.update!(status: "fulfilled")
    page = request(:get, "/dashboard/commerce/orders", site_id: @site.id)
    assert_equal 200, page.status
    assert_includes page.body, "Delete selected unpaid orders"
    assert_includes page.body, "form=\"delete-selected-orders\""
    assert_includes page.body, "select-order-#{order.id}"
    refute_includes page.body, "select-order-#{paid.id}"
    assert_equal 303, request(:delete, "/dashboard/commerce/orders/#{order.id}", site_id: @site.id).status
    assert order.reload.deleted_at?
    page = request(:get, "/dashboard/commerce/orders", site_id: @site.id)
    refute_includes page.body, "select-order-#{order.id}"
  end
  def test_foreign_site_or_foreign_order_in_bulk_cannot_be_deleted
    own = order_for(product)
    other = User.create!(role: "client", email_address: "other@example.com")
    foreign_site = DymondSite::Site.create!(tenant: other, host: "other.example.com")
    foreign = LightekCommerce::Order.create!(site: foreign_site, customer_email: "test@example.com")
    assert_equal 404, request(:delete, "/dashboard/commerce/orders", site_id: @site.id, order_ids: [own.id, foreign.id]).status
    refute own.reload.deleted_at?
    refute foreign.reload.deleted_at?
    assert_equal 404, request(:delete, "/dashboard/commerce/orders/#{own.id}", actor: other, site_id: @site.id).status
    assert_equal 404, request(:delete, "/dashboard/commerce/orders/#{foreign.id}", site_id: @site.id).status
  end
  def test_bulk_removes_only_eligible_orders_and_rejects_empty_selection
    pending = order_for(product)
    paid = order_for(product)
    paid.update!(status: "paid", paid_at: Time.current)
    assert_equal 303, request(:delete, "/dashboard/commerce/orders", site_id: @site.id, order_ids: []).status
    refute pending.reload.deleted_at?
    assert_equal 303, request(:delete, "/dashboard/commerce/orders", site_id: @site.id, order_ids: [pending.id, paid.id]).status
    assert pending.reload.deleted_at?
    refute paid.reload.deleted_at?
  end
  def test_role_restrictions_apply_to_deletion
    order = order_for(product)
    actor = User.create!(role: "employee", email_address: "employee@example.com")
    [actor, nil].each do |user|
      assert_equal 403, request(:delete, "/dashboard/commerce/orders/#{order.id}", actor: user, site_id: @site.id).status
    end
    refute order.reload.deleted_at?
  end
end
