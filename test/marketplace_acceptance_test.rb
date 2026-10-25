ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "rails/test_help"

module MarketplaceTestData
  def self.included(base)
    base.setup do
      # Rails fixture loading may clear migration seed rows. Every test owns
      # its required reference data inside the test transaction.
      DymondCatalog::MarketplaceListing::CATEGORIES.each_with_index do |(key, name), position|
        group = LightekMarketplace::ProductGroup.find_or_initialize_by(key: key)
        group.update!(name: name, position: position, active: true)
      end
    end
  end

  def marketplace_actor(role = "super_admin")
    User.create!(first_name: "Marketplace", last_name: "Acceptance", role: role,
      email_address: "marketplace-#{SecureRandom.hex(8)}@example.test",
      password: "Marketplace-acceptance-2026!", password_confirmation: "Marketplace-acceptance-2026!")
  end
  def product_values(overrides = {})
    {name: "Business Website #{SecureRandom.hex(3)}", description: "A home for your business.",
      category: "cloud", billing: "monthly", price: "29.00", setup_fee: "5.00", trial_days: 0,
      delivery: "manual", position: 0, welcome: "Welcome to Lightek."}.merge(overrides)
  end
  def connect_marketplace_service(feature, active: true)
    LightekMarketplace::CustomerService.create!(name: feature.name,
      description: "Customer access to #{feature.name}", feature_key: feature.key,
      customer_path: "/marketplace", active: active)
  end
  def create_marketplace_product(overrides = {}, published: true, **keyword_overrides)
    overrides = overrides.merge(keyword_overrides)
    form = LightekMarketplace::ProductForm.new(attributes: product_values(overrides))
    assert form.save(publish: published, actor: marketplace_actor), form.errors.full_messages.join("; ")
    form.listing
  end
end

class MarketplaceAcceptanceTest < ActionDispatch::IntegrationTest
  include MarketplaceTestData
  self.use_transactional_tests = true
  def sign_in(role)
    user = marketplace_actor(role)
    post "/session", params: {email_address: user.email_address, password: "Marketplace-acceptance-2026!"}
    assert_response :redirect
    user
  end

  test "storefront renders approved hero and five category links with CRUD About route" do
    get "/marketplace"
    assert_response :success
    assert_select "h1", /Everything you need/
    assert_select "nav[aria-label='Service categories'] a", 5
    assert_select "#lm-marketplace .lm-art h2", /Your platform/
  end
  test "real products show canonical billing amounts and category filters" do
    listing = create_marketplace_product
    get "/marketplace", params: {category: "cloud"}
    assert_response :success
    assert_select "h3", text: listing.title
    assert_select ".lm-price", /29/
    get "/marketplace", params: {category: "finance"}
    assert_select "h3", text: listing.title, count: 0
    get "/marketplace/#{listing.id}"
    assert_response :success
    assert_select "a[href*='checkout/marketplace-']", 1
  end
  test "draft products stay private and anonymous users cannot preview or administer" do
    listing = create_marketplace_product({}, published: false)
    get "/marketplace/#{listing.id}"
    assert_response :not_found
    get "/dashboard/marketplace/listings/#{listing.id}/preview"
    assert_includes [302, 303, 401, 403], response.status
    get "/dashboard/marketplace"
    assert_includes [302, 303, 401, 403], response.status
  end
  test "legacy HTML redirects and JSON route remains" do
    get "/catalogs"
    assert_redirected_to "/marketplace"
    assert_equal "catalogs", Rails.application.routes.recognize_path("/catalogs.json", method: :get)[:controller]
  end
  test "clients cannot create edit or publish products" do
    sign_in("client")
    get "/dashboard/marketplace/listings/new"
    assert_response :forbidden
    assert_no_difference ["DymondBank::Offer.count", "DymondBank::SubscriptionPlan.count", "DymondCatalog::MarketplaceListing.count"] do
      post "/dashboard/marketplace/listings", params: {marketplace_product: product_values, commit_action: "publish"}
    end
    assert_response :forbidden
    patch "/dashboard/marketplace/listings/0", params: {marketplace_product: product_values, commit_action: "publish"}
    assert_response :forbidden
  end
  test "super admin creates pricing and delivery without selecting an existing offer" do
    sign_in("super_admin")
    get "/dashboard/marketplace/listings/new"
    assert_response :success
    assert_select "[data-current-step='0']", 1
    assert_select "select[name='marketplace_product[billing]']", 0
    assert_select "button[value='next']", 1
    assert_select "select[name*='offer_id']", 0
    assert_difference "DymondCatalog::MarketplaceListing.count", 1 do
      assert_difference "DymondBank::Offer.count", 1 do
        post "/dashboard/marketplace/listings", params: {marketplace_product: product_values, commit_action: "publish"}
      end
    end
    assert_redirected_to "/dashboard/marketplace"
  end
  test "validation errors keep entered values and do not create billing records" do
    sign_in("super_admin")
    assert_no_difference ["DymondBank::Offer.count", "DymondBank::SubscriptionPlan.count"] do
      post "/dashboard/marketplace/listings", params: {marketplace_product: product_values(price: "-9"), commit_action: "publish"}
    end
    assert_response :unprocessable_entity
    assert_select "[role='alert']", /non-negative/
  end
  test "super admin can privately preview a draft and cannot buy it there" do
    listing = create_marketplace_product({}, published: false)
    sign_in("super_admin")
    get "/dashboard/marketplace/listings/#{listing.id}/preview"
    assert_response :success
    assert_select "h1", text: listing.title
    assert_select "a[href*='checkout']", 0
  end
end

class MarketplaceProductWorkflowTest < ActiveSupport::TestCase
  include MarketplaceTestData
  self.use_transactional_tests = true
  test "monthly annual one-time and free pricing round trips through Bank preview" do
    %w[monthly annual once free].each do |billing|
      listing = create_marketplace_product(billing: billing)
      offer = listing.offer
      p = DymondBank::Checkout.preview(offer: offer, interval: offer.default_interval)
      if %w[monthly annual].include?(billing)
        assert_equal 2900, p[:recurring_cents].to_i
        assert_equal 500, p[:setup_fee_cents].to_i
      elsif billing == "once"
        assert_nil offer.subscription_plan
        assert_equal 3400, p[:due_today_cents].to_i
      else
        assert_nil offer.subscription_plan
        assert_equal 0, p[:due_today_cents].to_i
      end
    end
  end
  test "trial defers recurring charge but retains setup fee" do
    listing = create_marketplace_product(trial_days: 14)
    p = DymondBank::Checkout.preview(offer: listing.offer, interval: "monthly")
    assert_equal 14, p[:trial_days].to_i
    assert_equal 500, p[:due_today_cents].to_i
  end
  test "editing makes new billing versions and leaves old plan and other offers unchanged" do
    listing = create_marketplace_product
    old = listing.offer
    original_plan = old.subscription_plan
    form = LightekMarketplace::ProductForm.new(listing: listing, attributes: {price: "39.00"})
    assert form.save(publish: true, actor: marketplace_actor), form.errors.full_messages.join("; ")
    assert_not_equal old.id, listing.reload.offer_id
    assert_equal 2900, original_plan.reload.price_monthly_cents
    assert_equal 3900, listing.offer.subscription_plan.price_monthly_cents
    assert_not old.reload.active?
  end
  test "stale edits do not replace newer product pricing" do
    listing = create_marketplace_product
    stale = LightekMarketplace::ProductForm.new(listing: listing, attributes: {revision: 0, price: "99"})
    assert_not stale.save(publish: true, actor: marketplace_actor)
    assert_equal 2900, listing.reload.offer.subscription_plan.price_monthly_cents
  end
  test "invalid amount precision or unsupported delivery rolls back all billing writes" do
    [{price: "1.999"}, {price: "NaN"}, {delivery: "unknown"}, {delivery: "website", billing: "once"}].each do |values|
      form = LightekMarketplace::ProductForm.new(attributes: product_values(values))
      assert_no_difference ["DymondBank::Offer.count", "DymondBank::SubscriptionPlan.count"] do
        assert_not form.save(publish: true, actor: marketplace_actor)
      end
    end
  end
  test "service layer rejects non-admin even outside HTTP" do
    form = LightekMarketplace::ProductForm.new(attributes: product_values)
    assert_raises(CanCan::AccessDenied) { form.save(publish: true, actor: marketplace_actor("client")) }
  end
end

class MarketplaceDeliveryTest < ActiveSupport::TestCase
  include MarketplaceTestData
  self.use_transactional_tests = true
  def order_for(listing, status: "paid", subscription: nil)
    DymondBank::Purchase.create!(offer: listing.offer, customer: marketplace_actor("client"),
      status: status, mode: listing.offer.mode, currency: "usd", amount_cents: 2900,
      billing_interval: listing.offer.default_interval, provision_spec: {}, subscription: subscription)
  end
  test "unpaid orders cannot produce delivery records" do
    listing = create_marketplace_product
    order = order_for(listing, status: "pending")
    assert_no_difference "Marlon::Ticket.count" do
      assert_raises(LightekMarketplace::Delivery::NotReady) { LightekMarketplace::Delivery.call(order) }
    end
  end
  test "manual delivery creates exactly one linked work request under repeated notifications" do
    order = order_for(create_marketplace_product)
    first = nil
    assert_difference "Marlon::Ticket.count", 1 do
      first = Marlon::Provisioning.fulfill(order).fetch(:marketplace_delivery)
      assert_equal first, Marlon::Provisioning.fulfill(order.reload).fetch(:marketplace_delivery)
    end
    assert_equal "work_requested", first["stage"]
    assert_equal "provisioning", order.reload.status
    assert_equal order.id, Marlon::Ticket.find(first["ticket_id"]).extra_fields["marketplace_purchase_id"]
  end
  test "website delivery requires subscription owned by customer" do
    listing = create_marketplace_product(delivery: "website")
    order = order_for(listing)
    assert_raises(LightekMarketplace::Delivery::NotReady) { LightekMarketplace::Delivery.call(order) }
  end
  test "website delivery creates one tenant site and reports pending activation" do
    listing = create_marketplace_product(delivery: "website")
    order = order_for(listing)
    subscription = DymondBank::Subscription.create!(subscriber: order.customer,
      plan: listing.offer.subscription_plan, status: "active", billing_interval: "monthly")
    order.update!(subscription: subscription)
    receipt = nil
    assert_difference "DymondSite::Site.count", 1 do
      receipt = LightekMarketplace::Delivery.call(order)
      assert_equal receipt, LightekMarketplace::Delivery.call(order.reload)
    end
    assert_equal "website_created", receipt["stage"]
    assert_equal true, receipt["activation_required"]
    assert DymondSite::Site.exists?(receipt["site_id"])
  end
  test "service access is granted once and canceled subscriptions revoke owned grants" do
    feature = Marlon::Feature.create!(name: "Marketplace customer service", key: "marketplace_test_#{SecureRandom.hex(4)}", active: true)
    connection = connect_marketplace_service(feature)
    listing = create_marketplace_product(delivery: "access", service_id: connection.id)
    order = order_for(listing)
    subscription = DymondBank::Subscription.create!(subscriber: order.customer,
      plan: listing.offer.subscription_plan, status: "active", billing_interval: "monthly")
    order.update!(subscription: subscription)
    assert_difference "UserFeatureEntitlement.count", 1 do
      LightekMarketplace::Delivery.call(order)
      LightekMarketplace::Delivery.call(order.reload)
    end
    grant = UserFeatureEntitlement.find_by!(user_id: order.customer_id, feature_slug: feature.key)
    assert grant.active?
    subscription.cancel!
    assert_not grant.reload.active?
    assert grant.revoked_at.present?
  end
  test "existing manually granted service access is not revoked by a marketplace cancellation" do
    feature = Marlon::Feature.create!(name: "Existing customer service", key: "marketplace_test_#{SecureRandom.hex(4)}", active: true)
    connection = connect_marketplace_service(feature)
    listing = create_marketplace_product(delivery: "access", service_id: connection.id)
    order = order_for(listing)
    subscription = DymondBank::Subscription.create!(subscriber: order.customer,
      plan: listing.offer.subscription_plan, status: "active", billing_interval: "monthly")
    order.update!(subscription: subscription)
    grant = UserFeatureEntitlement.create!(user_id: order.customer_id, feature_slug: feature.key, active: true, source: "manual", granted_at: Time.current)
    LightekMarketplace::Delivery.call(order)
    subscription.cancel!
    assert grant.reload.active?
    assert_equal "manual", grant.source
  end
  test "unmanaged purchases continue through existing fulfillment" do
    order = order_for(create_marketplace_product)
    order.offer.update!(meta: {})
    assert_not LightekMarketplace::Delivery.managed?(order)
  end
end

class MarketplaceBusinessWorkflowTest < ActionDispatch::IntegrationTest
  include MarketplaceTestData
  self.use_transactional_tests = true
  def login_as(role = "super_admin")
    user = marketplace_actor(role)
    post "/session", params: {email_address: user.email_address, password: "Marketplace-acceptance-2026!"}
    user
  end
  test "one product provides monthly and yearly prices at checkout" do
    listing = create_marketplace_product(billing: "both", monthly_price: "29.00", annual_price: "290.00")
    assert_equal %w[annual monthly], Array(listing.offer.available_intervals).map(&:to_s).sort
    get "/marketplace/#{listing.id}", params: {interval: "monthly"}
    assert_response :success
    assert_select "option[value='annual']", 1
    assert_select "a[href*='interval=monthly']", 1
    assert_match /29/, response.body
    get "/marketplace/#{listing.id}", params: {interval: "annual"}
    assert_response :success
    assert_select "a[href*='interval=annual']", 1
    assert_match /290/, response.body
    assert_equal 2900, listing.offer.subscription_plan.price_monthly_cents
    assert_equal 29000, listing.offer.subscription_plan.price_annual_cents
  end
  test "four step editor works through ordinary requests without creating intermediate billing records" do
    login_as
    values = product_values(billing: "both", monthly_price: "49.00", annual_price: "490.00")
    assert_no_difference ["DymondBank::Offer.count", "DymondBank::SubscriptionPlan.count", "DymondCatalog::MarketplaceListing.count"] do
      [0, 1, 2].each do |step|
        post "/dashboard/marketplace/listings", params: {marketplace_product: values, editor_step: step, commit_action: "next"}
        assert_response :success
        assert_select "[data-current-step='#{step + 1}']", 1
        assert_select "[data-current-step]", 1
        assert_select "input[name='marketplace_product[name]'][value='#{values[:name]}']", 1
      end
    end
    assert_difference "DymondCatalog::MarketplaceListing.count", 1 do
      post "/dashboard/marketplace/listings", params: {marketplace_product: values, editor_step: 3, commit_action: "publish"}
    end
    assert_redirected_to "/dashboard/marketplace"
  end
  test "admin creates and renames groups and storefront navigation follows" do
    login_as
    name = "Learning #{SecureRandom.hex(4)}"
    post "/dashboard/marketplace/groups", params: {product_group: {name: name, description: "Learning products", position: 5, active: true}}
    assert_redirected_to "/dashboard/marketplace/groups"
    group = LightekMarketplace::ProductGroup.find_by!(name: name)
    get "/marketplace"
    assert_select "nav[aria-label='Service categories'] a", text: name
    listing = create_marketplace_product(category: group.key)
    patch "/dashboard/marketplace/groups/#{group.id}", params: {product_group: {name: "Learning & Courses", active: true}}
    assert_redirected_to "/dashboard/marketplace/groups"
    assert_equal group.key, listing.reload.category
    assert_equal "Learning & Courses", DymondCatalog::MarketplaceListing.category_labels.fetch(group.key)
    patch "/dashboard/marketplace/groups/#{group.id}", params: {product_group: {active: false}}
    assert_response :unprocessable_entity
    assert group.reload.active?
  end
  test "clients cannot administer product groups or application connections" do
    login_as("client")
    %w[groups connections].each do |area|
      get "/dashboard/marketplace/#{area}"
      assert_response :forbidden
    end
    assert_no_difference "LightekMarketplace::ProductGroup.count" do
      post "/dashboard/marketplace/groups", params: {product_group: {name: "Unauthorized"}}
    end
    assert_response :forbidden
  end
  test "raw features never populate the product application chooser" do
    feature = Marlon::Feature.create!(key: "internal_#{SecureRandom.hex(4)}", name: "Internal feature must stay out", active: true)
    login_as
    post "/dashboard/marketplace/listings", params: {marketplace_product: product_values(delivery: "access"), editor_step: 2, commit_action: "refresh"}
    assert_response :success
    assert_select "select[name='marketplace_product[service_id]'] option", text: feature.name, count: 0
    draft = connect_marketplace_service(feature, active: false)
    get "/dashboard/marketplace/connections"
    assert_response :success
    assert_match /Draft connection/, response.body
    draft.update!(active: true)
    post "/dashboard/marketplace/listings", params: {marketplace_product: product_values(delivery: "access", service_id: draft.id), editor_step: 2, commit_action: "refresh"}
    assert_response :success
    assert_select "select[name='marketplace_product[service_id]'] option", text: draft.name
    assert_match /Customer opens:/, response.body
  end
  test "reviewed connections require an existing application page and non-administrative feature" do
    feature = Marlon::Feature.create!(key: "internal_#{SecureRandom.hex(4)}", name: "A real application", active: true)
    connection = LightekMarketplace::CustomerService.new(name: "Example", description: "A useful app", feature_key: feature.key, customer_path: "/does-not-exist", active: true)
    assert_not connection.valid?
    assert connection.errors[:customer_path].any?
    connection.customer_path = "https://example.com"
    assert_not connection.valid?
    connection.customer_path = "/marketplace"
    connection.feature_key = "vault"
    assert_not connection.valid?
    assert connection.errors[:feature_key].any?
  end
end
