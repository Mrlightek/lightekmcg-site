require "minitest/autorun"
require "minitest/mock"
require "active_record"
require "active_support/all"

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
class User < ApplicationRecord; end
class ProvisioningRequest < ApplicationRecord
  belongs_to :owner, class_name: "User"
  def gatekeeper_node = Struct.new(:ip_address, :status).new("203.0.113.7", "healthy")
end
module LightekCommerce
  class Order < ApplicationRecord
    self.table_name = "lightek_commerce_orders"
    belongs_to :hosting_owner, class_name: "User"
  end
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false
ActiveRecord::ConnectionAdapters::TableDefinition.alias_method :jsonb, :json
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :email_address; t.string :role }
  create_table(:provisioning_requests) { |t| t.references :owner }
  create_table(:lightek_commerce_orders) do |t|
    t.string :status
    t.datetime :paid_at
    t.datetime :provisioned_at
    t.string :provisioning_state
    t.string :hosting_domain
    t.references :hosting_owner
    t.references :provisioning_request
  end
end

require_relative "../../db/migrate/20261125160000_create_lightek_managed_dns_enrollments"
CreateLightekManagedDnsEnrollments.new.migrate(:up)
require_relative "../../app/services/gatekeeper/hosting/access"
require_relative "../../app/services/lightek_commerce/installations"
require_relative "../../app/services/lightek_settings/site_domain"
require_relative "../../app/models/lightek_managed_dns/enrollment"
require_relative "../../app/services/lightek_managed_dns/cloudflare"

class ManagedDnsChecks < Minitest::Test
  Enrollment = LightekManagedDns::Enrollment
  Brand = %w[ns1.lightekmcg.com ns2.lightekmcg.com].freeze
  Previous = %w[ns1.example.net ns2.example.net].freeze
  Provider = Struct.new(:status, :rows, :ns) do
    def zone!(_id, _domain) = {"status" => status}
    def nameservers!(_zone) = ns
    def records!(_id) = rows
  end

  def setup
    [Enrollment, LightekCommerce::Order, User, ProvisioningRequest].each(&:delete_all)
    @operator = User.create!(role: "super_admin")
    @owner = User.create!(role: "client")
    @request = ProvisioningRequest.create!(owner: @owner)
    @order = LightekCommerce::Order.create!(hosting_owner: @owner, provisioning_request_id: @request.id,
      hosting_domain: "store.example.com", status: "paid", provisioning_state: "ready",
      paid_at: Time.current, provisioned_at: Time.current)
    @provider = Provider.new("pending", [
      {"name"=>"store.example.com", "type"=>"A", "content"=>"203.0.113.7", "proxied"=>false},
      {"name"=>"example.com", "type"=>"MX", "content"=>"mx.example.net", "priority"=>10}
    ], Brand)
  end

  def request(actor = @owner)
    Enrollment.request!(order: @order, actor: actor)
  end

  def dns(enrollment, nameservers:, proof: true)
    resolver = lambda do |_name, type|
      case type.name.split("::").last
      when "NS" then nameservers.map { |server| Resolv::DNS::Resource::IN::NS.new(server) }
      when "A" then [Resolv::DNS::Resource::IN::A.new("203.0.113.7")]
      when "AAAA" then []
      when "TXT" then proof ? [Resolv::DNS::Resource::IN::TXT.new(enrollment.proof)] : []
      end
    end
    enrollment.stub(:resolve, resolver) { yield }
  end

  def test_enrollment_requires_opt_in_and_scope
    assert_nil Enrollment.find_by(order: @order)
    outsider = User.create!(role: "client")
    assert_raises(Enrollment::Invalid) { request(outsider) }
    agency = User.create!(role: "white_label")
    agency.define_singleton_method(:managed_account_ids) { [@owner_id] }
    agency.instance_variable_set(:@owner_id, @owner.id)
    enrollment = request(agency)
    assert_equal @owner.id, enrollment.owner_id
    assert_equal "example.com", enrollment.domain
    assert_equal enrollment.id, request.id
    assert_raises(Enrollment::Invalid) { enrollment.stage!(actor: agency, provider: @provider, zone_id: "test") }
  end

  def test_provider_and_public_dns_must_match_before_activation
    enrollment = request
    dns(enrollment, nameservers: Previous, proof: false) do
      assert_raises(Enrollment::Invalid) { enrollment.stage!(actor: @operator, provider: @provider, zone_id: "test") }
    end
    dns(enrollment, nameservers: Previous) do
      enrollment.stage!(actor: @operator, provider: @provider, zone_id: "test")
      enrollment.approve!(actor: @operator, provider: @provider)
      assert_raises(Enrollment::Invalid) { enrollment.verify!(provider: @provider) }
    end
    assert_equal "awaiting_delegation", enrollment.reload.state
    @provider.status = "active"
    dns(enrollment, nameservers: Brand) do
      enrollment.verify!(provider: @provider)
      assert_raises(Enrollment::Invalid) { enrollment.withdraw! }
    end
    assert_equal "active", enrollment.reload.state
    assert_equal @operator.id, enrollment.reviewed_by_id
    dns(enrollment, nameservers: Previous) { enrollment.withdraw! }
    assert_equal "withdrawn", enrollment.reload.state
  end

  def test_mail_record_changes_invalidate_the_review_snapshot
    enrollment = request
    dns(enrollment, nameservers: Previous) do
      enrollment.stage!(actor: @operator, provider: @provider, zone_id: "test")
      @provider.rows.pop
      assert_raises(Enrollment::Invalid) { enrollment.approve!(actor: @operator, provider: @provider) }
    end
    assert_equal "staged", enrollment.reload.state
  end

  def test_platform_names_cannot_enroll_through_customer_orders
    @order.update!(hosting_domain: "client-12.lightekmcg.com")
    assert_nil Enrollment.domain_for(@order)
    @order.update!(hosting_domain: "customer.example.co.uk")
    assert_equal "example.co.uk", Enrollment.domain_for(@order)
  end

  def test_provider_refuses_a_foreign_account_zone
    adapter = LightekManagedDns::Cloudflare.new(@operator)
    zone_id = "a" * 32
    ENV.stub(:[], ->(key) { key == "LIGHTEK_MANAGED_DNS_ACCOUNT_ID" ? "b" * 32 : nil }) do
      adapter.stub(:request, {"result"=>{"id"=>zone_id, "name"=>"example.com", "type"=>"full", "account"=>{"id"=>"c" * 32}}}) do
        assert_raises(LightekManagedDns::Cloudflare::Unavailable) { adapter.zone!(zone_id, "example.com") }
      end
    end
  end

  def test_provider_checks_the_assigned_account_set_and_its_public_addresses
    adapter = LightekManagedDns::Cloudflare.new(@operator)
    zone_id = "a" * 32
    account_id = "b" * 32
    zone = {"id" => zone_id, "account" => {"id" => account_id}}
    servers = Brand.map { |name| {"ns_name" => name, "ns_set" => 2, "dns_records" => [{"type" => "A", "value" => "203.0.113.8"}]} }
    responses = {
      "/zones/#{zone_id}/dns_settings" => {"result" => {"nameservers" => {"type" => "custom.account", "ns_set" => 2}}},
      "/accounts/#{account_id}/custom_ns" => {"result" => servers}
    }
    resolver = Object.new
    def resolver.timeouts=(_value); end
    resolver.define_singleton_method(:getaddresses) { |_name| ["203.0.113.8"] }
    with_resolver = ->(&block) { block.call(resolver) }
    adapter.stub(:request, responses.method(:fetch)) do
      Resolv::DNS.stub(:open, with_resolver) do
        assert_equal Brand, adapter.nameservers!(zone)
        servers.first.fetch("dns_records").first["value"] = "203.0.113.9"
        assert_raises(LightekManagedDns::Cloudflare::Unavailable) { adapter.nameservers!(zone) }
      end
    end
  end
end
