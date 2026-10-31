# frozen_string_literal: true

require "test_helper"

class GatekeeperDeletedNodeReconciliationTest < ActiveSupport::TestCase
  def stub_method(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name) { |*args, **kwargs| implementation.call(*args, **kwargs) }
    yield
  ensure
    object.define_singleton_method(name, original)
  end

  def setup
    @owner = User.create!(email_address: "reconcile-#{SecureRandom.hex(6)}@example.test",
      first_name: "Node", last_name: "Owner", role: "client", password: "test-password-123")
    @provider = ComputeProvider.create!(name: "Linode test #{SecureRandom.hex(4)}",
      slug: "linode-test-#{SecureRandom.hex(4)}", status: "active", health_status: "healthy")
    @node = GatekeeperNode.create!(name: "reconcile-#{SecureRandom.hex(6)}",
      ip_address: "203.0.113.44", ssh_user: "root", ssh_port: 22,
      compute_provider: @provider, provider_resource_id: "12345", owner: @owner)
    @request = ProvisioningRequest.create!(owner: @owner, gatekeeper_node: @node,
      compute_provider: @provider, approval_status: "auto_approved",
      execution_status: "succeeded", requested_node_count: 1,
      metadata: {"allocation_attempted" => true, "provider_resource_id" => "12345"})
  end

  test "existing provider node stays attached" do
    adapter = Object.new
    adapter.define_singleton_method(:node) { |_| {"id" => 12345} }
    stub_method(@provider, :adapter, ->(**) { adapter }) do
      assert_equal false, Gatekeeper::Compute::DeletedNodeReconciliation.call!(
        request: @request, requested_by: "operator@example.test")
    end
    assert_equal @node.id, @request.reload.gatekeeper_node_id
  end

  test "provider 404 with empty inventory retires node and preserves history" do
    adapter = Object.new
    adapter.define_singleton_method(:node) { |_| raise StandardError, "Provider HTTP 404: not found" }
    adapter.define_singleton_method(:nodes) { [] }
    stub_method(@provider, :adapter, ->(**) { adapter }) do
      assert_equal true, Gatekeeper::Compute::DeletedNodeReconciliation.call!(
        request: @request, requested_by: "operator@example.test")
    end
    assert_nil @request.reload.gatekeeper_node_id
    assert_equal "decommissioned", @node.reload.status
    assert_equal @node.id, @request.metadata.fetch("retired_provider_nodes").last.fetch("node_id")
    refute @request.metadata.key?("allocation_attempted")
  end

  test "provider uncertainty cannot authorize replacement" do
    adapter = Object.new
    adapter.define_singleton_method(:node) { |_| raise StandardError, "Provider HTTP 503: unavailable" }
    stub_method(@provider, :adapter, ->(**) { adapter }) do
      assert_raises(StandardError) do
        Gatekeeper::Compute::DeletedNodeReconciliation.call!(
          request: @request, requested_by: "operator@example.test")
      end
    end
    assert_equal @node.id, @request.reload.gatekeeper_node_id
  end
end
