require "test_helper"

class ProvisioningExecutionRecoveryTest < ActiveSupport::TestCase
  Service = Gatekeeper::Compute::ProvisioningExecutionService

  test "matches only the precise order-bound provider label and request tag" do
    request = Struct.new(:id, :node_label).new(42, "lightek-client-42")
    nodes = [
      {"id" => 1, "label" => "lightek-client-42", "tags" => ["other-request"]},
      {"id" => 2, "label" => "lightek-client-99", "tags" => ["provisioning-request-42"]},
      {"id" => 3, "label" => "lightek-client-42", "tags" => ["provisioning-request-42"]}
    ]
    assert_equal [3], Service.matching_provider_nodes(nodes, request).map { |node| node["id"] }
  end

  test "refuses ambiguous provider recovery instead of selecting a random VPS" do
    request = Struct.new(:id, :node_label).new(42, "lightek-client-42")
    nodes = (1..2).map { |id|
      {"id" => id, "label" => "lightek-client-42", "tags" => ["provisioning-request-42"]}
    }
    assert_raises(Service::ProviderResponseError) { Service.matching_provider_nodes(nodes, request) }
  end

  test "absent provider candidates are reported empty" do
    request = Struct.new(:id, :node_label).new(42, "lightek-client-42")
    assert_empty Service.matching_provider_nodes([], request)
  end
end
