# frozen_string_literal: true
require "test_helper"

class NevaehAtomicStudioClaimV2fTest < ActiveSupport::TestCase
  test "only the exact Nevaeh Studio handler is in scope" do
    model = Struct.new(:kind, :handler)
    assert NevaehIntelligences::AtomicStudioClaimV2f.target?(model.new("studio.project.create", "Studio::Workers::ProjectCreation"))
    refute NevaehIntelligences::AtomicStudioClaimV2f.target?(model.new("studio.project.create", "Unrelated::Handler"))
    refute NevaehIntelligences::AtomicStudioClaimV2f.target?(model.new("billing.charge", "Studio::Workers::ProjectCreation"))
  end

  test "database claim is one-time and cannot be replayed" do
    item = DymondDispatch::WorkItem.create!(
      kind: "studio.project.create", handler: "Studio::Workers::ProjectCreation",
      queue: "default", status: "queued", args: ["create", { "name" => "V2F claim only" }],
      dispositions: [{ "kind" => "nevaeh", "on" => "any" }],
      correlation_id: SecureRandom.uuid
    )
    assert NevaehIntelligences::AtomicStudioClaimV2f.claim!(item.id, worker_id: "v2f:test:first")
    refute NevaehIntelligences::AtomicStudioClaimV2f.claim!(item.id, worker_id: "v2f:test:replay")
    item.reload
    assert_equal "working", item.status
    assert_equal "v2f:test:first", item.worker_id
    assert_equal 1, item.attempts
  end

  test "original execution Gatekeeper remains wired into invoke" do
    assert_includes DymondDispatch::PerformWorkItemJob.ancestors, NevaehV2fAtomicStudioPerform
    assert_includes DymondDispatch::PerformWorkItemJob.ancestors, NevaehV2fWorkerInvokeGuard
  end
end
