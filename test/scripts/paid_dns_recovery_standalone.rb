# frozen_string_literal: true
# Run without private gems: ruby test/scripts/paid_dns_recovery_standalone.rb
# Exercises real service orchestration with doubles only at DB/provider boundaries.
require "minitest/autorun"

class Object
  def blank? = respond_to?(:empty?) ? !!empty? : !self
  def present? = !blank?
  def presence = self if present?
end
class String
  def blank? = strip.empty?
end

require_relative "../../app/services/godaddy/dns_service"
require_relative "../../app/services/gatekeeper/website_dns_publication"
require_relative "../../app/services/gatekeeper/website_deployment"
require_relative "../../app/services/lightek_commerce/paid_instance_provisioning"

module DymondDash
  class Notification
    def self.find_or_create_by!(**) = raise("Unexpected notification publication")
  end
end

class User
  def self.find(*) = raise("Unexpected database access")
  def self.find_by!(**) = raise("Unexpected operator lookup")
end
module LightekVault
  class Secret
    def self.exists?(**) = raise("Unexpected Vault lookup")
  end
  class Service
    class AccessDenied < StandardError; end
    def self.checkout!(**) = raise("Unexpected Vault checkout")
  end
end
module Rails
  def self.env = Struct.new(:production?).new(true)
end
module LightekCommerce
  class Order
    def self.find(*) = raise("Unexpected order lookup")
  end
  class PaidInstanceProvisioningJob
    def self.perform_now(*) = raise("Unexpected job dispatch")
  end
end
class ProvisioningRequest
  def self.find(*) = raise("Unexpected request lookup")
end
module Gatekeeper::Compute
  class ProvisioningExecutionService
    def self.call(**) = raise("Unexpected allocation")
  end
  class NodeVerificationService
    def self.call(**) = raise("Unexpected provider verification")
  end
end

class PaidDnsRecoveryStandaloneTest < Minitest::Test
  Dns = Gatekeeper::WebsiteDnsPublication
  Deployment = Gatekeeper::WebsiteDeployment
  Request = Struct.new(:owner, :gatekeeper_node_id, :gatekeeper_node) do
    def executable? = true
    def reload = self
  end
  Node = Struct.new(:id, :ip_address, :provider_resource_id) do
    def reload = self
  end

  def setup
    @owner = Struct.new(:email_address).new("owner@example.test")
    @request = Request.new(@owner)
    @config = {"owner_id" => 1, "credential_slug" => "owner-password"}
  end

  def with_deployment
    Deployment.stub(:preview, @config) do
      User.stub(:find, @owner) { yield }
    end
  end

  def test_shared_resolver_selects_longest_managed_zone_without_token_override
    options = []
    service = Object.new
    service.define_singleton_method(:verify_access!) { true }
    service.define_singleton_method(:records) do
      [{"name" => "client-1", "type" => "A", "data" => "8.8.8.8"}]
    end
    Godaddy::DnsService.stub(:zones, ["example.test", "clients.example.test"]) do
      Godaddy::DnsService.stub(:new, ->(**args) { options << args; service }) do
        assert Dns.preflight!(hostname: "client-1.clients.example.test")
        Resolv.stub(:getaddresses, ["8.8.8.8"]) do
          assert Dns.call!(hostname: "client-1.clients.example.test", ipv4: "8.8.8.8")["verified"]
        end
      end
    end
    assert_equal [{zone: "clients.example.test"}, {zone: "clients.example.test"}], options
  end

  def test_unmanaged_platform_zone_is_refused_before_provider
    Godaddy::DnsService.stub(:zones, []) do
      assert_raises(Dns::NotConfigured) { Dns.preflight!(hostname: "client-1.lightekmcg.com") }
    end
  end

  def test_dns_denial_prevents_billable_allocation
    allocated = false
    secret = {"owner_password" => String.new("owner-password")}
    with_deployment do
      LightekVault::Service.stub(:checkout!, secret) do
        Dns.stub(:preflight!, ->(**) { raise Godaddy::DnsService::ConfigurationError, "denied" }) do
          Gatekeeper::Compute::ProvisioningExecutionService.stub(:call, ->(**) { allocated = true }) do
            assert_raises(Godaddy::DnsService::ConfigurationError) do
              Deployment.provision_and_run!(actor: @owner, request: @request, domain: "client-1.example.test")
            end
          end
        end
      end
    end
    refute allocated
    assert_empty secret["owner_password"]
  end

  def test_owner_only_credential_passes_preflight_before_allocation
    events = []
    stopped = Class.new(StandardError)
    with_deployment do
      LightekVault::Service.stub(:checkout!, {"owner_password" => String.new("owner-password")}) do
        Dns.stub(:preflight!, ->(hostname:) { events << [:dns, hostname] }) do
          Gatekeeper::Compute::ProvisioningExecutionService.stub(:call, ->(**) { events << [:allocation]; raise stopped }) do
            assert_raises(stopped) do
              Deployment.provision_and_run!(actor: @owner, request: @request, domain: "client-1.example.test")
            end
          end
        end
      end
    end
    assert_equal [[:dns, "client-1.example.test"], [:allocation]], events
  end

  def test_retry_reuses_existing_node_without_owner_vault_dns_checkout
    node = Node.new(12, "8.8.8.8", "12345")
    @request.gatekeeper_node = node
    @request.gatekeeper_node_id = node.id
    events = []
    with_deployment do
      Deployment.stub(:register!, ->(**) { events << :registered }) do
        Gatekeeper::Compute::NodeVerificationService.stub(:call, {provider_status: "running"}) do
          Dns.stub(:call!, ->(**args) { assert_equal({hostname: "client-1.example.test", ipv4: "8.8.8.8"}, args); events << :published }) do
            Deployment.stub(:run!, ->(**) { events << :installed; {verified: true} }) do
              assert Deployment.provision_and_run!(actor: @owner, request: @request, domain: "client-1.example.test")[:verified]
            end
          end
        end
      end
    end
    assert_equal [:registered, :published, :installed], events
  end

  def test_multiple_a_records_fail_even_when_one_matches
    service = Object.new
    service.define_singleton_method(:records) do
      ["8.8.8.8", "9.9.9.9"].map { |ip| {"name" => "client-1", "type" => "A", "data" => ip} }
    end
    Godaddy::DnsService.stub(:zones, ["example.test"]) do
      Godaddy::DnsService.stub(:new, service) do
        assert_raises(Dns::Conflict) { Dns.call!(hostname: "client-1.example.test", ipv4: "8.8.8.8") }
      end
    end
  end

  def test_private_address_is_rejected
    assert_raises(ArgumentError) { Dns.call!(hostname: "client-1.example.test", ipv4: "127.0.0.1") }
  end

  def test_dns_management_uses_scoped_vault_checkout
    Godaddy::DnsService.stub(:zones, ["example.test"]) do
      LightekVault::Secret.stub(:exists?, true) do
        LightekVault::Service.stub(:checkout!, ->(**options) {
          assert_equal "godaddy-dns", options[:slug]
          assert_equal "Godaddy::DnsService", options[:consumer]
          assert_equal "dns_management", options[:purpose]
          {"token" => "test-vault-token"}
        }) do
          assert_equal "test-vault-token", Godaddy::DnsService.new(zone: "example.test").send(:token)
        end
      end
    end
  end

  def test_vault_denial_fails_without_using_a_legacy_token
    Godaddy::DnsService.stub(:zones, ["example.test"]) do
      LightekVault::Secret.stub(:exists?, true) do
        LightekVault::Service.stub(:checkout!, ->(**) { raise LightekVault::Service::AccessDenied }) do
          assert_raises(Godaddy::DnsService::ConfigurationError) do
            Godaddy::DnsService.new(zone: "example.test").send(:token)
          end
        end
      end
    end
  end

  def test_recovery_script_delegates_to_locked_job_without_destroying_an_active_node
    order = Struct.new(:id, :status, :customer_email, :provisioning_request_id,
                       :provisioning_state, :provisioning_error, :attributes).new(
      1, "paid", @owner.email_address, 9, "ready", nil,
      {"paid_at" => "already-paid", "payment_reference" => "existing-reference",
       "total_cents" => 2500, "currency" => "usd"})
    order.define_singleton_method(:paid_at?) { true }
    order.define_singleton_method(:provisioned_at?) { true }
    order.define_singleton_method(:reload) { self }
    provider = Struct.new(:slug).new("linode")
    provider.define_singleton_method(:adapter) { |**| raise "Recovery script must not call or destroy provider resources outside the job lock" }
    request = Struct.new(:id, :subscription_id, :owner, :compute_provider).new(9, 21, @owner, provider)
    request.define_singleton_method(:reload) { self }
    dispatched = []
    Rails.stub(:env, Struct.new(:production?).new(true)) do
      LightekCommerce::Order.stub(:find, order) do
        ProvisioningRequest.stub(:find, request) do
          User.stub(:find_by!, @owner) do
            LightekCommerce::PaidInstanceProvisioningJob.stub(:perform_now, ->(id) { dispatched << id }) do
              out, = capture_io { load File.expand_path("../../script/lightek/rebuild_paid_instance.rb", __dir__) }
              assert_includes out, "PAID_PAYMENT_AND_SUBSCRIPTION_PRESERVED"
            end
          end
        end
      end
    end
    assert_equal [1], dispatched
  end

  def test_recovery_script_refuses_nonproduction_before_reading_order
    Rails.stub(:env, Struct.new(:production?).new(false)) do
      error = assert_raises(RuntimeError) do
        load File.expand_path("../../script/lightek/rebuild_paid_instance.rb", __dir__)
      end
      assert_includes error.message, "production application runtime"
    end
  end
  def test_ready_notice_is_idempotent_and_does_not_require_email_delivery
    order = Struct.new(:status, :provisioning_state, :paid_at?, :provisioned_at?).new("paid", "ready", true, true)
    locks = 0
    order.define_singleton_method(:with_lock) { |&block| locks += 1; block.call }
    records = {}
    factory = ->(**attributes, &block) do
      records[attributes] ||= begin
        notification = Struct.new(:body, :url).new
        block.call(notification)
        notification
      end
    end
    DymondDash::Notification.stub(:find_or_create_by!, factory) do
      2.times { LightekCommerce::PaidInstanceProvisioning.publish_ready_notification!(order: order, customer: @owner, domain: "client-1.example.test") }
    end
    assert_equal 2, locks
    assert_equal 1, records.size
    assert_equal "https://client-1.example.test", records.values.first.url
  end

  def test_incomplete_installation_cannot_publish_ready_notice
    order = Struct.new(:status, :provisioning_state, :paid_at?, :provisioned_at?).new("paid", "deploying", true, false)
    order.define_singleton_method(:with_lock) { |&block| block.call }
    assert_raises(LightekCommerce::PaidInstanceProvisioning::NotReady) do
      LightekCommerce::PaidInstanceProvisioning.publish_ready_notification!(order: order, customer: @owner, domain: "client-1.example.test")
    end
  end

end
