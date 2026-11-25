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
require_relative "../../db/migrate/20261125180000_add_provider_to_managed_dns_enrollments"
AddProviderToManagedDnsEnrollments.new.migrate(:up)
require_relative "../../app/services/gatekeeper/hosting/access"
require_relative "../../app/services/lightek_commerce/installations"
require_relative "../../app/services/lightek_settings/site_domain"
require_relative "../../app/models/lightek_managed_dns/enrollment"
require_relative "../../app/services/lightek_managed_dns/cloudflare"
require_relative "../../app/services/lightek_managed_dns/power_dns"
require_relative "../../app/services/lightek_managed_dns/dns_probe"
require "stringio"

module Rails
  def self.logger = @logger ||= Logger.new(File::NULL)
end

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
    Enrollment.stub(:configured_provider, "cloudflare") { Enrollment.request!(order: @order, actor: actor) }
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

  def test_powerdns_requires_both_replicas_before_registrar_handoff
    enrollment = Enrollment.stub(:configured_provider, "powerdns") { Enrollment.request!(order: @order, actor: @owner) }
    assert_instance_of LightekManagedDns::PowerDns, enrollment.provider_for(@operator)
    provider = LightekManagedDns::PowerDns.new(@operator)
    provider.stub(:zone!, {"name" => "example.com."}) do
      provider.stub(:records!, @provider.rows) do
        provider.stub(:nameservers!, Brand) do
          dns(enrollment, nameservers: Previous) do
            provider.stub(:verify_authority!, ->(*) { raise LightekManagedDns::PowerDns::Unavailable }) do
              assert_raises(LightekManagedDns::PowerDns::Unavailable) { enrollment.stage!(actor: @operator, provider: provider, zone_id: enrollment.domain) }
            end
            assert_equal "requested", enrollment.reload.state
            provider.stub(:verify_authority!, true) do
              enrollment.stage!(actor: @operator, provider: provider, zone_id: enrollment.domain)
              enrollment.approve!(actor: @operator, provider: provider)
            end
          end
          dns(enrollment, nameservers: Brand) do
            provider.stub(:verify_authority!, true) { enrollment.verify!(provider: provider) }
          end
        end
      end
    end
    assert_equal "active", enrollment.reload.state
  end

  def test_powerdns_record_changes_are_scoped_and_version_checked
    enrollment = request
    enrollment.update!(provider_kind: "powerdns", state: "active", nameservers: Brand, provider_zone_id: enrollment.domain)
    provider = LightekManagedDns::PowerDns.new(@owner)
    rows = @provider.rows
    params = {record_name: "@", record_type: "MX", ttl: "600", record_values: "10 new-mail.example.net.\n", revision: enrollment.record_revision(rows)}
    changes = []
    provider.stub(:zone!, {"name" => "example.com."}) do
      provider.stub(:records!, rows) do
        provider.stub(:write_rrset!, ->(**values) { changes << values; :notified }) do
          dns(enrollment, nameservers: Brand) do
            assert_raises(Enrollment::Invalid) { enrollment.change_rrset!(actor: User.create!(role: "client"), provider: provider, attributes: params) }
            assert_raises(Enrollment::Invalid) { enrollment.change_rrset!(actor: @owner, provider: provider, attributes: params.merge(revision: "stale")) }
            assert_raises(Enrollment::Invalid) { enrollment.change_rrset!(actor: @owner, provider: provider, attributes: params.merge(record_name: "other.example.net")) }
            assert_raises(Enrollment::Invalid) { enrollment.change_rrset!(actor: @owner, provider: provider, attributes: params.merge(record_name: @order.hosting_domain, record_type: "A")) }
            enrollment.change_rrset!(actor: @owner, provider: provider, attributes: params)
            enrollment.change_rrset!(actor: @owner, provider: provider, attributes: params, remove: true)
          end
          dns(enrollment, nameservers: Previous) do
            assert_raises(Enrollment::Invalid) { enrollment.change_rrset!(actor: @owner, provider: provider, attributes: params) }
          end
        end
      end
    end
    assert_equal ["10 new-mail.example.net."], changes.first[:contents]
    assert_equal "example.com", changes.first[:domain]
    assert_equal [false, true], changes.pluck(:remove)
  end

  def test_powerdns_uses_the_primary_rrset_api
    provider = LightekManagedDns::PowerDns.new(@operator)
    observed = []
    provider.stub(:request, ->(*args) { observed << args }) do
      provider.write_rrset!(domain: "example.com", name: "example.com", type: "MX", ttl: 600,
        contents: ["10 mail.example.net."], remove: false)
    end
    method, path, data = observed.first
    assert_equal Net::HTTP::Patch, method
    assert_equal "/api/v1/servers/localhost/zones/example.com.", path
    assert_equal [{"name"=>"example.com.", "type"=>"MX", "changetype"=>"REPLACE", "ttl"=>600,
      "records"=>[{"content"=>"10 mail.example.net.", "disabled"=>false}]}], data.fetch("rrsets")
    assert_equal [Net::HTTP::Put, "#{path}/notify"], observed.last
  end

  def test_powerdns_verifies_every_public_address_serves_the_primary_serial
    provider = LightekManagedDns::PowerDns.new(@operator)
    endpoint_map = {Brand.first => ["203.0.113.8"], Brand.last => ["203.0.113.9"]}
    resolver = Object.new
    def resolver.timeouts=(_value); end
    resolver.define_singleton_method(:getaddresses) { |name| endpoint_map.fetch(name.delete_suffix(".")) }
    observed = []
    lagging = true
    answers = lambda do |ip, _name, type|
      observed << ip
      case type.name.split("::").last
      when "SOA" then [Struct.new(:serial).new(lagging && ip == endpoint_map.fetch(Brand.last).first ? 41 : 42)]
      when "NS" then Brand.map { |host| Resolv::DNS::Resource::IN::NS.new(host) }
      when "A" then [Resolv::DNS::Resource::IN::A.new("203.0.113.7")]
      when "AAAA" then []
      end
    end
    provider.stub(:public_endpoints!, endpoint_map) do
      Resolv::DNS.stub(:open, ->(&block) { block.call(resolver) }) do
        LightekManagedDns::DnsProbe.stub(:answers, answers) do
          zone = {"name" => "example.com.", "serial" => 42}
          arguments = {nameservers: Brand, website: "store.example.com", ip: "203.0.113.7"}
          assert_raises(LightekManagedDns::PowerDns::Unavailable) { provider.verify_authority!(zone, **arguments) }
          lagging = false
          observed.clear
          provider.verify_authority!(zone, **arguments)
          assert_equal endpoint_map.values.flatten, observed.uniq
        end
      end
    end
  end

  def test_probe_requires_an_authoritative_answer_to_the_exact_question
    resource = Resolv::DNS::Resource::IN::A
    [0, 1].each do |authoritative|
      reply = Resolv::DNS::Message.new(111)
      reply.qr = 1
      reply.aa = authoritative
      reply.add_question("store.example.com.", resource)
      reply.add_answer("store.example.com.", 300, resource.new("203.0.113.7"))
      data = reply.encode
      buffer = StringIO.new([data.bytesize].pack("n") + data)
      wire = Struct.new(:buffer) do
        def write(_query) = nil
        def read(size) = buffer.read(size)
      end.new(buffer)
      Socket.stub(:tcp, ->(*, **, &block) { block.call(wire) }) do
        SecureRandom.stub(:random_number, 111) do
          if authoritative == 1
            assert_equal ["203.0.113.7"], LightekManagedDns::DnsProbe.answers("203.0.113.8", "store.example.com.", resource).map { |answer| answer.address.to_s }
          else
            assert_raises(LightekManagedDns::DnsProbe::Unavailable) { LightekManagedDns::DnsProbe.answers("203.0.113.8", "store.example.com.", resource) }
          end
        end
      end
    end
  end
end
