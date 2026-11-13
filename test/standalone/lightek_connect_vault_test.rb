require_relative "lightek_connect_api_test"

class LightekConnectVaultTest < Minitest::Test
  include ConnectVaultFixtures
  def setup
    reset_shopify_vault!
    @operator = User.create!(role: "super_admin", email_address: "operator@example.test")
  end
  def credentials = LightekConnect::ShopifyCredentials
  def test_store_encrypts_secret_and_audits_runtime_checkout
    credentials.store!(actor: @operator, client_id: "new-client-id", client_secret: "new-client-secret")
    row = LightekVault::Secret.find_by!(slug: credentials::SLUG)
    refute row.ciphertext.include?("new-client-secret")
    refute row.metadata.to_json.include?("new-client-secret")
    assert_equal "new-client-id", credentials.client_id
    assert credentials.status[:stored]
    audit = LightekVault::AuditEvent.last
    assert audit.allowed
    assert_equal "LightekConnect::ShopifyCredentials", audit.consumer
    assert_equal "shopify_connect", audit.purpose
  end
  def test_missing_vault_entry_does_not_fall_back_to_environment
    LightekVault::AuditEvent.delete_all
    LightekVault::Secret.delete_all
    ENV["LIGHTEK_SHOPIFY_CLIENT_ID"] = "environment-id"
    ENV["LIGHTEK_SHOPIFY_CLIENT_SECRET"] = "environment-secret"
    assert_raises(credentials::Unavailable) { credentials.client_id }
  ensure
    ENV.delete("LIGHTEK_SHOPIFY_CLIENT_ID")
    ENV.delete("LIGHTEK_SHOPIFY_CLIENT_SECRET")
  end
  def test_disabled_expired_and_denied_entries_fail_closed
    row = LightekVault::Secret.find_by!(slug: credentials::SLUG)
    [{status: "disabled"}, {status: "active", expires_at: 1.second.ago},
     {expires_at: nil, access_policy: {"consumers" => ["SomeoneElse"], "purposes" => ["shopify_connect"]}}].each do |attributes|
      row.update!(attributes)
      assert_raises(credentials::Unavailable) { credentials.client_id }
      refute LightekVault::AuditEvent.last.allowed
    end
  end
  def test_corrupted_ciphertext_is_not_replaced_or_bypassed
    row = LightekVault::Secret.find_by!(slug: credentials::SLUG)
    row.update!(ciphertext: "corrupted")
    assert_raises(credentials::Unavailable) { credentials.client_id }
    assert_equal "corrupted", row.reload.ciphertext
  end
  def test_rotation_applies_to_next_request_without_restart
    assert_equal "test-client", credentials.client_id
    credentials.store!(actor: @operator, client_id: "rotated-client", client_secret: "rotated-secret")
    claims = {"aud" => "rotated-client", "dest" => "https://agency.myshopify.com", "iss" => "https://agency.myshopify.com/admin", "sub" => "123", "exp" => Time.now.to_i + 60, "nbf" => Time.now.to_i - 1}
    token = JWT.encode(claims, "rotated-secret", "HS256")
    assert_equal "agency.myshopify.com:123", LightekConnect::Shopify.identity!("Bearer #{token}")
    old_token = JWT.encode(claims.merge("aud" => "test-client"), "test-secret", "HS256")
    assert_raises(LightekConnect::Shopify::Invalid) { LightekConnect::Shopify.identity!("Bearer #{old_token}") }
  end
  def test_plaintext_checkout_is_cleared_after_use_and_on_error
    payload = nil
    credentials.with_credentials { |value| payload = value; assert_equal "test-secret", value["client_secret"] }
    assert payload.values.all?(&:empty?)
    assert_raises(ArgumentError) { credentials.with_credentials { |value| payload = value; raise ArgumentError } }
    assert payload.values.all?(&:empty?)
  end
  def test_invalid_save_preserves_existing_credential
    assert_raises(ArgumentError) { credentials.store!(actor: @operator, client_id: "test-client", client_secret: "") }
    assert_equal "test-client", credentials.client_id
  end
  def test_agency_cannot_replace_shared_application_credentials
    agency = User.create!(role: "white_label")
    assert_raises(Gatekeeper::Hosting::Access::Denied) { credentials.store!(actor: agency, client_id: "hijacked-client", client_secret: "hijacked-secret") }
    assert_equal "test-client", credentials.client_id
  end
end

# Exercise the real settings action with the Rails auth/engine boundary isolated.
class ApplicationController < ActionController::Base
  attr_accessor :current_user
end
module Dashboard; end
require Rails.root.join("app/controllers/dashboard/connect_shopify_settings_controller")
class LightekConnectShopifySettingsTest < ActionController::TestCase
  tests Dashboard::ConnectShopifySettingsController
  include ConnectVaultFixtures
  def setup
    reset_shopify_vault!
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      get "/dashboard/connect", to: "dashboard/connect#index", as: :dashboard_connect
      patch "/dashboard/connect/shopify", to: "dashboard/connect_shopify_settings#update"
    end
    @controller.singleton_class.include(@routes.url_helpers)
    @controller.current_user = User.create!(role: "super_admin", email_address: "operator@example.test")
    @request.headers["X-CSRF-Token"] = @controller.send(:form_authenticity_token)
  end
  def test_super_admin_can_save_via_dashboard_without_redisplaying_secret
    patch :update, params: {shopify: {client_id: "dashboard-client", client_secret: "dashboard-secret"}}
    assert_response :redirect
    assert_equal "dashboard-client", LightekConnect::ShopifyCredentials.client_id
    refute response.body.include?("dashboard-secret")
    refute flash.to_hash.to_json.include?("dashboard-secret")
  end
  def test_missing_csrf_token_cannot_save_credentials
    @request.headers["X-CSRF-Token"] = nil
    assert_raises(ActionController::InvalidAuthenticityToken) do
      patch :update, params: {shopify: {client_id: "forged-client", client_secret: "forged-secret"}}
    end
    assert_equal "test-client", LightekConnect::ShopifyCredentials.client_id
  end
  def test_agency_is_forbidden
    @controller.current_user = User.create!(role: "white_label")
    patch :update, params: {shopify: {client_id: "hijacked-client", client_secret: "hijacked-secret"}}
    assert_response :forbidden
    assert_equal "test-client", LightekConnect::ShopifyCredentials.client_id
  end
end
