# frozen_string_literal: true
require "test_helper"

class InstallationsFlowTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ActiveJob::TestHelper
  PASSWORD = "installation-test-password"

  setup do
    ActiveJob::Base.queue_adapter = :test
    ApplicationJob.queue_adapter = ActiveJob::Base.queue_adapter
    @buyer = create_user("client")
    @other = create_user("client")
    @operator = create_user("super_admin")
    @merchant = create_user("admin")
    @site = DymondSite::Site.create!(name: "Installation test", host: "install-#{SecureRandom.hex(8)}.example.test", tenant: @merchant)
    @plan = DymondBank::SubscriptionPlan.create!(name: "Installation", slug: "installation-#{SecureRandom.hex(6)}", price_monthly_cents: 2500)
    @product = LightekCommerce::Product.create!(site: @site, name: "Application", slug: "application", product_type: "lightek_instance",
      subscription_plan_id: @plan.id, price_cents: 2500, inventory_quantity: 20, published: true)
    @order = LightekCommerce::Order.create!(site: @site, customer_email: @buyer.email_address, status: "paid", paid_at: Time.current,
      provisioning_state: "ready", provisioned_at: Time.current, subtotal_cents: 2500, total_cents: 2500)
    @order.items.create!(product: @product, name: @product.name, quantity: 1, unit_price_cents: 2500, line_total_cents: 2500)
  end

  test "anonymous visitors must sign in before viewing an installation" do
    get installation_path(@order)
    assert_redirected_to new_session_path
  end

  test "client can see owned installation and password setup control without operator role" do
    sign_in(@buyer)
    get installation_path(@order)
    assert_response :success
    assert_select "h1", "Your application is ready"
    assert_select "form[action='#{access_installation_path(@order)}']"
    assert_includes response.headers["Cache-Control"], "no-store"
    get installation_path(@order, format: :json)
    assert_response :success
    assert_equal @order.id, response.parsed_body["id"]
    refute response.body.include?("credential_slug")
    refute response.body.include?("owner_password")
  end

  test "another buyer cannot read or obtain access to an installation" do
    sign_in(@other)
    get installation_path(@order, format: :json)
    assert_response :not_found
    Gatekeeper::WebsiteDeployment.stub(:owner_password_setup_url!, ->(**) { flunk "unauthorized access reached Gatekeeper" }) do
      post access_installation_path(@order)
      assert_response :not_found
    end
  end

  test "merchant operator can track orders but cannot obtain buyer password setup" do
    sign_in(@merchant)
    get dashboard_installations_path
    assert_response :success
    assert_select "td", text: /#{Regexp.escape(@buyer.email_address)}/
    get installation_path(@order)
    assert_response :not_found
  end

  test "super admin can inspect every installation and reach its account setup" do
    sign_in(@operator)
    get dashboard_installations_path
    assert_response :success
    get installation_path(@order)
    assert_response :success
  end

  test "owned password handoff redirects only through Gatekeeper and is not cached" do
    sign_in(@buyer)
    Gatekeeper::WebsiteDeployment.stub(:owner_password_setup_url!, ->(actor:, order:) {
      assert_equal @buyer.id, actor.id
      assert_equal @order.id, order.id
      "https://client-#{order.id}.example.test/passwords/native-token/edit"
    }) do
      post access_installation_path(@order)
      assert_response :see_other
      assert_equal "https://client-#{@order.id}.example.test/passwords/native-token/edit", response.location
      assert_includes response.headers["Cache-Control"], "no-store"
      assert_equal "same-origin", response.headers["Referrer-Policy"]
      assert Rails.application.env_config.fetch("action_dispatch.redirect_filter").any? { |filter| filter === response.location }
    end
  end

  test "browser password button submits its rendered token with same-origin CSRF protection" do
    sign_in(@buyer)
    previous = InstallationsController.allow_forgery_protection
    InstallationsController.allow_forgery_protection = true
    get installation_path(@order)
    assert_response :success
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    form = Nokogiri::HTML(response.body).at_css("form[action='#{access_installation_path(@order)}']")
    token = form.at_css('input[name="authenticity_token"]')["value"]
    assert token.present?
    Gatekeeper::WebsiteDeployment.stub(:owner_password_setup_url!, ->(**) { "https://client.example.test/passwords/native-token/edit" }) do
      post form["action"], params: {authenticity_token: token}, headers: {"HTTP_ORIGIN" => "http://www.example.com"}
      assert_response :see_other
    end
  ensure
    InstallationsController.allow_forgery_protection = previous
  end

  test "null and foreign origins remain rejected by the password handoff" do
    sign_in(@buyer)
    previous = InstallationsController.allow_forgery_protection
    InstallationsController.allow_forgery_protection = true
    get installation_path(@order)
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')["content"]
    Gatekeeper::WebsiteDeployment.stub(:owner_password_setup_url!, ->(**) { flunk "Foreign origin reached Gatekeeper" }) do
      ["null", "https://untrusted.example"].each do |origin|
        post access_installation_path(@order), params: {authenticity_token: token}, headers: {"HTTP_ORIGIN" => origin}
        assert_response :unprocessable_entity
      end
    end
  ensure
    InstallationsController.allow_forgery_protection = previous
  end

  test "failed paid installation resumes the same order without checkout" do
    @order.update!(provisioned_at: nil, provisioning_state: "failed")
    sign_in(@buyer)
    # Observe dispatch at the queue boundary: this test's outer DB transaction
    # intentionally never commits, while Rails defers actual enqueue to commit.
    dispatched = []
    LightekCommerce::PaidInstanceProvisioningJob.stub(:perform_later, ->(id) { dispatched << id }) do
      post retry_installation_installation_path(@order)
    end
    assert_redirected_to installation_path(@order)
    assert_equal [@order.id], dispatched
    assert_equal "queued", @order.reload.provisioning_state
    assert_equal 1, LightekCommerce::Order.where(customer_email: @buyer.email_address).count
  end

  test "unpaid installation cannot start provisioning" do
    @order.update!(status: "pending_payment", paid_at: nil, provisioned_at: nil, provisioning_state: nil)
    sign_in(@buyer)
    LightekCommerce::PaidInstanceProvisioningJob.stub(:perform_later, ->(*) { flunk "Unpaid order reached the queue" }) do
      post retry_installation_installation_path(@order)
    end
    assert_redirected_to installations_path
  end

  test "repeated checkout form reuses the order and the buyer identity" do
    sign_in(@buyer)
    key = SecureRandom.uuid
    calls = []
    LightekCommerce::StripeCheckout.stub(:start!, ->(order:, **_) {
      calls << order.id
      Struct.new(:url).new("https://checkout.stripe.com/c/pay/test-checkout")
    }) do
      2.times { post installations_path, params: {product_id: @product.id, checkout_key: key, customer_email: @other.email_address} }
    end
    assert_response :see_other
    assert_equal 1, calls.uniq.size
    order = LightekCommerce::Order.find(calls.first)
    assert_equal @buyer.email_address, order.customer_email
    assert_equal "pending_payment", order.status
    assert_nil order.paid_at
    assert_nil order.provisioning_request_id
  end

  test "native setup changes a password and invalidates its setup token" do
    token = @buyer.generate_token_for(:password_reset)
    get edit_password_path(token)
    assert_response :success
    put password_path(token), params: {password: "chosen-installation-password", password_confirmation: "chosen-installation-password"}
    assert_redirected_to new_session_path
    assert @buyer.reload.authenticate("chosen-installation-password")
    get edit_password_path(token)
    assert_redirected_to new_password_path
  end


  test "JSON password handoff requires CSRF protection even with a signed session" do
    sign_in(@buyer)
    previous = InstallationsController.allow_forgery_protection
    InstallationsController.allow_forgery_protection = true
    Gatekeeper::WebsiteDeployment.stub(:owner_password_setup_url!, ->(**) { flunk "CSRF failure reached Gatekeeper" }) do
      post access_installation_path(@order), as: :json
      assert_response :unprocessable_entity
    end
  ensure
    InstallationsController.allow_forgery_protection = previous
  end

  private

  def create_user(role)
    User.create!(email_address: "installation-#{SecureRandom.hex(8)}@example.test", first_name: "Install", last_name: "Test", role: role, password: PASSWORD)
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: PASSWORD}
    assert_response :redirect
  end
end
