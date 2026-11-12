# Run: ruby test/standalone/lightek_connect_test.rb
# Real migrations/models and authorization; no private engine gems required.
gem "minitest", "~> 5.0"
require "minitest/autorun"
require "minitest/mock"
require "active_record"
require "active_support/all"
require "jwt"
require "pathname"
require "ostruct"
module Rails
  def self.root = Pathname.new(File.expand_path("../..", __dir__))
end
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false
ActiveRecord::ConnectionAdapters::TableDefinition.class_eval { alias_method :jsonb, :json }
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :role; t.string :email_address; t.integer :agency_id; t.integer :upstream_share_bps, default: 0 }
  create_table(:sessions) { |t| t.references :user }
  create_table(:dymond_site_sites) { |t| t.string :name; t.string :host; t.references :tenant, polymorphic: true }
end
migration = Rails.root.join("db/migrate/20261112190000_create_lightek_connect.rb").read.sub("Migration[8.0]", "Migration[7.2]")
eval(migration, TOPLEVEL_BINDING)
CreateLightekConnect.new.migrate(:up)
require Rails.root.join("app/models/concerns/account_hierarchy")
class User < ApplicationRecord
  include AccountHierarchy
  belongs_to :agency, class_name: "User", optional: true
  def agency_profile = nil
end
module DymondSite
  class Site < ApplicationRecord
    self.table_name = "dymond_site_sites"
    belongs_to :tenant, polymorphic: true
    def pages = Struct.new(:unused) { def each; end }.new
  end
end
module LightekReservations
  class Peer
    def self.find_by(**) = nil
  end
end
module NevaehControlCenterHelper; end
require Rails.root.join("app/services/gatekeeper/hosting/access")
require Rails.root.join("app/services/lightek_settings/website_identity")
%w[connection event grant].each { |name| require Rails.root.join("app/models/lightek_connect/#{name}") }
%w[shopify workspace instance_transport].each { |name| require Rails.root.join("app/services/lightek_connect/#{name}") }

class LightekConnectTest < Minitest::Test
  def setup
    LightekConnect::Event.delete_all
    LightekConnect::Grant.delete_all
    LightekConnect::Connection.delete_all
    DymondSite::Site.delete_all
    User.delete_all
    @agency = User.create!(role: "white_label", email_address: "agency@example.test")
    @client = User.create!(role: "client", email_address: "client@example.test", agency: @agency)
    @other = User.create!(role: "client", email_address: "other@example.test")
    @site = DymondSite::Site.create!(name: "Client", host: "client.example.test", tenant: @client)
    @foreign_site = DymondSite::Site.create!(name: "Other", host: "other.example.test", tenant: @other)
    @connection, @code = LightekConnect::Connection.issue!(user: @agency, platform: "wordpress", label: "Agency WP")
    ENV["LIGHTEK_SHOPIFY_CLIENT_ID"] = "test-client"
    ENV["LIGHTEK_SHOPIFY_CLIENT_SECRET"] = "test-secret"
  end
  def pair
    LightekConnect::Connection.redeem!(code: @code, platform: "wordpress", identity: nil)
  end
  def test_pairing_is_single_use_and_credentials_are_digested
    connection, token = pair
    assert_equal connection, LightekConnect::Connection.authenticate(token)
    refute_equal token, connection.token_digest
    assert_nil connection.code_digest
    assert_raises(ActiveRecord::RecordNotFound) { pair }
  end
  def test_expired_pairing_code_is_denied
    @connection.update!(code_expires_at: 1.second.ago)
    assert_raises(Gatekeeper::Hosting::Access::Denied) { pair }
  end
  def test_platform_bound_pairing_code
    assert_raises(ActiveRecord::RecordNotFound) { LightekConnect::Connection.redeem!(code: @code, platform: "shopify", identity: "shop:1") }
  end
  def test_client_cannot_issue_agency_connection
    assert_raises(Gatekeeper::Hosting::Access::Denied) { LightekConnect::Connection.issue!(user: @client, platform: "wordpress", label: "Forbidden") }
  end
  def test_role_change_invalidates_existing_connection
    _, token = pair
    @agency.update!(role: "client")
    assert_nil LightekConnect::Connection.authenticate(token)
  end
  def test_revocation_invalidates_connection_and_pending_grant
    connection, token = pair
    code = LightekConnect::Grant.issue!(connection: connection, site: @site)
    connection.revoke!
    assert_nil LightekConnect::Connection.authenticate(token)
    assert_raises(Gatekeeper::Hosting::Access::Denied) { LightekConnect::Grant.consume!(code: code, site: @site) }
  end
  def test_grant_bound_to_site_and_single_use
    pair
    code = LightekConnect::Grant.issue!(connection: @connection, site: @site)
    assert_raises(ActiveRecord::RecordNotFound) { LightekConnect::Grant.consume!(code: code, site: @foreign_site) }
    assert LightekConnect::Grant.consume!(code: code, site: @site).consumed_at
    assert_raises(Gatekeeper::Hosting::Access::Denied) { LightekConnect::Grant.consume!(code: code, site: @site) }
  end
  def test_grant_rechecks_client_relationship
    pair
    code = LightekConnect::Grant.issue!(connection: @connection, site: @site)
    @client.update!(agency: nil)
    assert_raises(Gatekeeper::Hosting::Access::Denied) { LightekConnect::Grant.consume!(code: code, site: @site) }
  end
  def test_expired_grant_denied
    pair
    code = LightekConnect::Grant.issue!(connection: @connection, site: @site)
    LightekConnect::Grant.last.update!(expires_at: 1.second.ago)
    assert_raises(Gatekeeper::Hosting::Access::Denied) { LightekConnect::Grant.consume!(code: code, site: @site) }
  end
  def test_dashboard_grant_supports_no_site
    pair
    code = LightekConnect::Grant.issue!(connection: @connection, site: nil, destination: "/dashboard/servers")
    assert_equal "/dashboard/servers", LightekConnect::Grant.consume!(code: code, site: nil).destination
  end
  def test_external_and_traversal_destinations_are_rejected
    ["https://evil.test", "//evil.test", "/dashboard/../evil"].each do |destination|
      assert_raises(ArgumentError) { LightekConnect::Grant.issue!(connection: @connection, site: nil, destination: destination) }
    end
  end
  def test_other_agency_site_is_inaccessible
    workspace = LightekConnect::Workspace.new(@connection)
    assert_raises(ActiveRecord::RecordNotFound) { workspace.rename!(@foreign_site.id, "Hijacked") }
    assert_raises(Gatekeeper::Hosting::Access::Denied) { LightekConnect::Grant.issue!(connection: @connection, site: @foreign_site) }
    assert_equal "Other", @foreign_site.reload.name
  end
  def test_save_persists_and_verifies_actual_site
    result = LightekConnect::Workspace.new(@connection).rename!(@site.id, "  New client name  ")
    assert_equal "New client name", @site.reload.name
    assert result[:verified]
    assert_equal "website_renamed", LightekConnect::Event.last.action
  end
  def test_remote_save_uses_authoritative_instance_and_preserves_ledger
    workspace = LightekConnect::Workspace.new(@connection)
    peer = Object.new
    response = {"host" => @site.host, "name" => "Remote name", "verified" => true}
    workspace.stub(:remote_peer, peer) do
      LightekConnect::InstanceTransport.stub(:rename!, response) do
        assert workspace.rename!(@site.id, "Remote name")["verified"]
      end
    end
    assert_equal "Client", @site.reload.name
    assert_equal true, LightekConnect::Event.last.details["remote"]
  end
  def test_nested_client_is_accessible
    child = User.create!(role: "white_label", agency: @agency)
    @client.update!(agency: child)
    assert LightekConnect::Workspace.new(@connection).rename!(@site.id, "Nested")[:verified]
  end
  def jwt(overrides = {}, secret = "test-secret", algorithm = "HS256")
    claims = {"aud" => "test-client", "dest" => "https://agency.myshopify.com", "iss" => "https://agency.myshopify.com/admin", "sub" => "123", "exp" => Time.now.to_i + 60, "nbf" => Time.now.to_i - 1}.merge(overrides).reject { |_, value| value.nil? }
    "Bearer #{JWT.encode(claims, secret, algorithm)}"
  end
  def test_shopify_identity_bound_to_shop_and_staff_member
    assert_equal "agency.myshopify.com:123", LightekConnect::Shopify.identity!(jwt)
    assert_equal "agency.myshopify.com:456", LightekConnect::Shopify.identity!(jwt({"sub" => "456"}))
  end
  def test_invalid_shopify_sessions_rejected
    [{"aud" => "wrong"}, {"dest" => "https://evil.test"}, {"iss" => "https://other.myshopify.com/admin"}, {"exp" => Time.now.to_i - 1}, {"nbf" => Time.now.to_i + 90}, {"sub" => ""}, {"exp" => nil}].each do |claims|
      assert_raises(LightekConnect::Shopify::Invalid) { LightekConnect::Shopify.identity!(jwt(claims)) }
    end
    assert_raises(LightekConnect::Shopify::Invalid) { LightekConnect::Shopify.identity!(jwt({}, "wrong")) }
    assert_raises(LightekConnect::Shopify::Invalid) { LightekConnect::Shopify.identity!(jwt({}, nil, "none")) }
  end
  def test_webhook_signature_verifies_exact_body
    body = '{"shop_id":12}'
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "test-secret", body))
    assert LightekConnect::Shopify.webhook_valid?(body, signature)
    refute LightekConnect::Shopify.webhook_valid?(body + " ", signature)
  end
  def test_instance_transport_blocks_private_networks
    %w[127.0.0.1 10.0.0.1 169.254.169.254 ::1 fc00::1 ::ffff:127.0.0.1].each do |address|
      assert LightekConnect::InstanceTransport::FORBIDDEN.any? { |range| range.include?(IPAddr.new(address)) }
    end
    refute LightekConnect::InstanceTransport::FORBIDDEN.any? { |range| range.include?(IPAddr.new("8.8.8.8")) }
  end
end
