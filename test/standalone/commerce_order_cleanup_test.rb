# Run against the real commerce models and transactions, without private gems.
require_relative "commerce_hosting_test"
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
    helper_method :current_user
    rescue_from(ActiveRecord::RecordNotFound) { head :not_found }
  end
end
module Dashboard; end
require Rails.root.join("app/controllers/dashboard/settings_home_controller").to_s
require Rails.root.join("app/controllers/dashboard/commerce_base_controller").to_s
require Rails.root.join("app/controllers/dashboard/commerce_orders_controller").to_s
require Rails.root.join("app/controllers/dashboard/commerce_returns_controller").to_s
require Rails.root.join("app/services/lightek_settings/website_identity").to_s
Dashboard::CommerceOrdersController.prepend_view_path(Rails.root.join("app/views"))
Dashboard::CommerceOrdersController.layout false
Dashboard::CommerceReturnsController.prepend_view_path(Rails.root.join("app/views"))
Dashboard::CommerceReturnsController.layout false
CLEANUP_ROUTES = ActionDispatch::Routing::RouteSet.new
CLEANUP_ROUTES.draw do
  instance_eval(File.readlines(Rails.root.join('config/routes.rb')).grep(%r{"/dashboard/commerce/(returns|orders/:order_id/returns[^"]*)"}).join)
  get "/dashboard/commerce/orders", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_orders
  get "/dashboard/commerce/disputes", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_disputes
  delete "/dashboard/commerce/orders", to: "dashboard/commerce_orders#bulk_destroy"
  delete "/dashboard/commerce/orders/:order_id", to: "dashboard/commerce_orders#destroy", as: :dashboard_commerce_order
  get "/dashboard/installations", to: "dashboard/commerce_orders#index", as: :dashboard_installations
  get "/dashboard/commerce/payouts", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_payouts
  get "/dashboard/commerce/products", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_products
  post "/dashboard/commerce/orders/:order_id/fulfill", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_fulfill
  post "/dashboard/commerce/orders/:order_id/refund", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_refund
  get "/dashboard/commerce/products/new", to: "dashboard/commerce_orders#index", as: :new_dashboard_commerce_product
  patch "/dashboard/commerce/products/:id", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_product
  post "/dashboard/commerce/products/:product_id/variants", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_variants
  delete "/dashboard/commerce/products/:product_id/variants/:id", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_variant
end
Dashboard::CommerceOrdersController.include(CLEANUP_ROUTES.url_helpers)
Dashboard::CommerceOrdersController.helper(CLEANUP_ROUTES.url_helpers)
Dashboard::CommerceReturnsController.include(CLEANUP_ROUTES.url_helpers)
Dashboard::CommerceReturnsController.helper(CLEANUP_ROUTES.url_helpers)
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
  def test_merchants_set_and_view_a_return_fee_through_the_dashboard
    order = order_for(product(product_type: 'physical', billing_interval: 'one_time'))
    order.update!(status: 'fulfilled', paid_at: Time.current, fulfilled_at: Time.current,
      payment_provider: 'stripe', payment_reference: 'cs_dashboard_return_fee')
    returns = LightekCommerce::MerchandiseReturns.new(order: order, actor: @operator)
    record = returns.request!(item_id: order.items.sole.id, quantity: 1, reason: 'Wrong size', request_key: SecureRandom.uuid)
    base = "/dashboard/commerce/orders/#{order.id}/returns"
    assert_includes request(:get, base, site_id: @site.id).body, 'Return fee in cents'
    response = request(:post, "#{base}/#{record.id}", site_id: @site.id, operation: 'approve', refund_fee_cents: '125')
    assert_equal 303, response.status
    assert_equal ['approved', 125], record.reload.attributes.values_at('status', 'refund_fee_cents')
    assert_includes request(:get, base, site_id: @site.id).body, 'Return fee $1.25'
  end

  def test_private_return_label_upload_download_and_revocation
    order = order_for(product(product_type: 'physical', billing_interval: 'one_time'))
    order.update!(status: 'fulfilled', paid_at: Time.current, fulfilled_at: Time.current)
    returns = LightekCommerce::MerchandiseReturns.new(order: order, actor: @operator)
    record = returns.request!(item_id: order.items.sole.id, quantity: 1, reason: 'Wrong size', request_key: SecureRandom.uuid)
    path = "/dashboard/commerce/orders/#{order.id}/returns/#{record.id}"
    pdf = "%PDF-1.4\nlabel fixture\n%%EOF\n"
    file = ->(contents) { Rack::Test::UploadedFile.new(StringIO.new(contents), 'application/pdf', original_filename: 'label.pdf') }
    upload = ->(contents, **extra) do
      request(:post, path, site_id: @site.id, operation: 'upload_label', label_pdf: file.call(contents), **extra)
    end

    assert_equal 303, upload.call(pdf).status
    assert_empty LightekCommerce::ReturnLabel.list_for([record.reload])
    returns.approve!(record.id)
    assert_equal 303, upload.call('<html>bad</html>').status
    assert_equal 303, upload.call(pdf, carrier: 'ups', tracking_number: 'https://bad.test').status
    assert_equal 404, request(:get, "#{path}/label", site_id: @site.id).status
    assert_equal 303, upload.call(pdf, carrier: 'fedex', tracking_number: '123456789012').status
    page = request(:get, "/dashboard/commerce/orders/#{order.id}/returns", site_id: @site.id)
    assert_equal 200, page.status
    assert_includes page.body, 'https://www.fedex.com/fedextrack/?trknbr=123456789012'
    response = request(:get, "#{path}/label", site_id: @site.id)
    assert_equal 200, response.status
    assert_equal pdf, response.body
    assert_includes response.headers.fetch('content-disposition'), 'attachment'
    assert_includes response.headers.fetch('cache-control'), 'no-store'
    assert_equal 'nosniff', response.headers.fetch('x-content-type-options')
    foreign = DymondSite::Site.create!(tenant: @operator, host: 'return-label-other.test')
    assert_equal 404, request(:get, "#{path}/label", site_id: foreign.id).status
    assert_equal 303, upload.call(pdf.sub('fixture', 'replacement')).status
    assert_equal 1, LightekCommerce::ReturnLabel.where(merchandise_return_id: record.id).count
    returns.cancel!(record.id)
    assert_equal 404, request(:get, "#{path}/label", site_id: @site.id).status
  end

  def test_return_queue_links_to_the_order_and_rejects_an_independent_store
    order = order_for(product(product_type: 'physical', billing_interval: 'one_time'))
    order.update!(status: 'fulfilled', paid_at: Time.current, fulfilled_at: Time.current)
    return_record = LightekCommerce::MerchandiseReturns.new(order: order, actor: @operator).request!(
      item_id: order.items.sole.id, quantity: 1, reason: 'Wrong size', request_key: SecureRandom.uuid)
    page = request(:get, '/dashboard/commerce/returns', site_id: @site.id)
    assert_equal 200, page.status
    assert_includes page.body, "#return-#{return_record.id}"
    assert_includes page.headers.fetch('cache-control'), 'no-store'
    detail = request(:get, "/dashboard/commerce/orders/#{order.id}/returns", site_id: @site.id)
    assert_equal 200, detail.status
    assert_includes detail.body, 'Wrong size'
    foreign = DymondSite::Site.create!(tenant: @operator, host: 'return-http-other.test')
    assert_equal 404, request(:get, "/dashboard/commerce/orders/#{order.id}/returns", site_id: foreign.id).status
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

  def test_paid_order_actions_have_separate_labeled_fields_and_preserve_payment_parameters
    orders = 2.times.map { order_for(product).tap { |order| order.update!(status: "paid", paid_at: Time.current) } }
    page = request(:get, "/dashboard/commerce/orders", site_id: @site.id)
    assert_equal 200, page.status
    html = Nokogiri::HTML(page.body)
    assert_equal 2, html.css("details.dd-order-manage").size
    orders.each do |order|
      reference = html.at_css("#order_#{order.id}_fulfillment_reference")
      assert_equal "fulfillment_reference", reference["name"]
      assert html.at_css("label[for='#{reference['id']}']")
      refund = html.at_css("#order_#{order.id}_refund_amount")
      assert_equal "amount_cents", refund["name"]
      assert_equal order.total_cents.to_s, refund["max"]
      assert html.at_css("##{refund['aria-describedby']}")
    end
    ids = html.css("[id]").map { |element| element["id"] }
    assert_equal ids.uniq, ids, "each order needs unique label targets"
    assert_empty html.css("form form"), "action forms must never nest"
  end

  def test_empty_order_list_has_a_useful_next_action
    page = request(:get, "/dashboard/commerce/orders", site_id: @site.id)
    assert_equal 200, page.status
    assert_includes page.body, "A fresh start for your storefront"
    refute_includes page.body, "delete-selected-orders"
  end
end
