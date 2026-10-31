# frozen_string_literal: true
require "test_helper"

class PaidInstanceAllocationReconciliationTest < ActiveSupport::TestCase
  FakeRequest = Struct.new(:id, :node_label)

  test "finds exactly one existing provider node by request tag and label" do
    request = FakeRequest.new(42, "lightek-client-42")
    nodes = [
      {"id" => 101, "label" => "lightek-client-42", "tags" => ["lightek-managed", "provisioning-request-42"]},
      {"id" => 102, "label" => "lightek-client-42", "tags" => ["provisioning-request-43"]},
      {"id" => 103, "label" => "unrelated", "tags" => ["provisioning-request-42"]}
    ]
    result = Gatekeeper::Compute::ProvisioningExecutionService.matching_provider_nodes(nodes, request)
    assert_equal [101], result.map { |node| node.fetch("id") }
  end

  test "does not reconcile a node with a matching label but missing ownership tag" do
    request = FakeRequest.new(42, "lightek-client-42")
    nodes = [{"id" => 101, "label" => "lightek-client-42", "tags" => []}]
    assert_empty Gatekeeper::Compute::ProvisioningExecutionService.matching_provider_nodes(nodes, request)
  end

  test "rejects ambiguous provider resources instead of selecting an arbitrary VPS" do
    request = FakeRequest.new(42, "lightek-client-42")
    nodes = [101, 102].map do |id|
      {"id" => id, "label" => "lightek-client-42", "tags" => ["provisioning-request-42"]}
    end
    assert_raises(Gatekeeper::Compute::ProvisioningExecutionService::ProviderResponseError) do
      Gatekeeper::Compute::ProvisioningExecutionService.matching_provider_nodes(nodes, request)
    end
  end
end
