# frozen_string_literal: true
require "test_helper"
class NevaehExecutionGateV2fTest < ActiveSupport::TestCase
  FakeItem = Struct.new(:kind, :handler, :subject_type, :subject_id, :correlation_id, :id, :args)

  test "generic dispatch handlers remain outside this gate" do
    item = FakeItem.new("invoices", "Billing::SendInvoice", nil, nil, nil, 123, [])
    assert_equal false, NevaehIntelligences::ExecutionGateV2f.guarded?(item)
    assert NevaehIntelligences::ExecutionGateV2f.require_allowed!(item)
  end

  test "Nevaeh Studio execution fails closed without the original ticket" do
    item = FakeItem.new("studio.project.create", "Studio::Workers::ProjectCreation", nil, nil, "123", 123, ["create", {"name" => "blocked"}])
    assert NevaehIntelligences::ExecutionGateV2f.guarded?(item)
    assert_raises(NevaehIntelligences::ExecutionGateV2f::Denied) do
      NevaehIntelligences::ExecutionGateV2f.require_allowed!(item)
    end
  end

  test "DymondDispatch worker has the execution gate hook" do
    assert_includes DymondDispatch::PerformWorkItemJob.ancestors, NevaehV2fWorkerInvokeGuard
  end
end
