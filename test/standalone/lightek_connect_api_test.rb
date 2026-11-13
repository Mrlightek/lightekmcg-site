# Real HTTP controller tests, isolated from private Rails engine dependencies.
require_relative "lightek_connect_test"
require "action_controller"
require "action_controller/test_case"
module Rails
  def self.env = ActiveSupport::StringInquirer.new("test")
  def self.application = nil
end
module Api; end
require Rails.root.join("app/controllers/api/connect_controller")
class LightekConnectApiTest < ActionController::TestCase
  include ConnectVaultFixtures
  tests Api::ConnectController
  def setup
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      post "/pair", to: "api/connect#pair"
      get "/workspace", to: "api/connect#show"
      patch "/sites/:id", to: "api/connect#update_site"
      delete "/connection", to: "api/connect#disconnect"
    end
    @agency = User.create!(role: "white_label", email_address: "http-agency@example.test")
    @client = User.create!(role: "client", agency: @agency)
    @site = DymondSite::Site.create!(name: "HTTP client", host: "http.example.test", tenant: @client)
    @connection, @code = LightekConnect::Connection.issue!(user: @agency, platform: "wordpress", label: "HTTP")
    @request.host = "lightekmcg.com"
    reset_shopify_vault!
  end
  def test_cookie_without_connector_credential_is_rejected
    get :show, format: :json
    assert_response :unauthorized
  end
  def test_pair_then_save_and_revoke_over_http
    post :pair, params: {platform: "wordpress", code: @code}, format: :json
    assert_response :success
    token = JSON.parse(response.body).fetch("token")
    @request.headers["Authorization"] = "Bearer #{token}"
    patch :update_site, params: {id: @site.id, name: "HTTP save"}, format: :json
    assert_response :success
    assert_equal "HTTP save", @site.reload.name
    assert JSON.parse(response.body).fetch("verified")
    delete :disconnect, format: :json
    assert_response :no_content
    patch :update_site, params: {id: @site.id, name: "Revoked"}, format: :json
    assert_response :unauthorized
    assert_equal "HTTP save", @site.reload.name
  end
  def test_cross_client_write_is_rejected_over_http
    _, token = LightekConnect::Connection.redeem!(code: @code, platform: "wordpress", identity: nil)
    stranger = User.create!(role: "client")
    site = DymondSite::Site.create!(name: "Foreign", tenant: stranger, host: "foreign.example.test")
    @request.headers["Authorization"] = "Bearer #{token}"
    patch :update_site, params: {id: site.id, name: "Hijack"}, format: :json
    assert_response :not_found
    assert_equal "Foreign", site.reload.name
  end
  def test_shopify_returns_unavailable_when_vault_credentials_are_disabled
    LightekVault::Service.disable!(slug: LightekConnect::ShopifyCredentials::SLUG, requested_by: "test-operator")
    @request.headers["Authorization"] = "Bearer invalid.jwt.signature"
    post :pair, params: {platform: "shopify", code: @code}, format: :json
    assert_response :service_unavailable
    refute response.body.include?("test-secret")
  end
  def test_invalid_shopify_pairing_is_unauthorized
    @request.headers["Authorization"] = "Bearer invalid.jwt.signature"
    post :pair, params: {platform: "shopify", code: @code}, format: :json
    assert_response :unauthorized
  end
end

require Rails.root.join("app/controllers/concerns/lightek_connect/delegated_session")
class Session < ApplicationRecord
  belongs_to :user
end
class Current < ActiveSupport::CurrentAttributes
  attribute :session
end
class ConnectSessionProbeController < ActionController::Base
  include LightekConnect::DelegatedSession
  def current_user = Current.session&.user
  def index = render(json: {ok: true})
  def terminate_session
    Current.session.destroy
    Current.session = nil
  end
end
class LightekConnectDelegatedSessionTest < ActionController::TestCase
  tests ConnectSessionProbeController
  def setup
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw { get "/probe", to: "connect_session_probe#index" }
    @actor = User.create!(role: "white_label")
    @connection, = LightekConnect::Connection.issue!(user: @actor, platform: "wordpress", label: "Session test")
    @session = Session.create!(user: @actor, connect_delegation: {"connection_id" => @connection.id, "local" => true})
    Current.session = @session
  end
  def teardown
    Current.reset
  end
  def test_connected_session_is_allowed
    get :index
    assert_response :success
  end
  def test_revocation_ends_delegated_session_on_next_request
    @connection.revoke!
    get :index
    assert_response :unauthorized
    assert_nil Current.session
    refute Session.exists?(@session.id)
  end
  def test_normal_client_session_is_not_subject_to_connector_revocation
    @session.update!(connect_delegation: {})
    @connection.revoke!
    get :index
    assert_response :success
    assert Session.exists?(@session.id)
  end
end
