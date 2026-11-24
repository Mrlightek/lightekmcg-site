require "test_helper"

class ItServicesTransitionTest < ActiveSupport::TestCase
  test "rejects unauthorized actor before changing state" do
    request = ItServiceRequest.new(status: "requested")
    actor = User.new(role: "client")
    assert_raises(ArgumentError) do
      ItServices::Transition.call!(request: request, actor: actor, to: "resolved", note: "done")
    end
  end

  test "rejects empty notes before changing state" do
    request = ItServiceRequest.new(status: "requested")
    actor = User.new(role: "super_admin")
    assert_raises(ArgumentError) do
      ItServices::Transition.call!(request: request, actor: actor, to: "triaged", note: "")
    end
  end
  test "admin transition cannot bypass technician and customer verification" do
    refute_includes ItServices::Transition::ALLOWED.fetch("in_progress"), "resolved"
    refute_includes ItServices::Transition::ALLOWED.fetch("scheduled"), "in_progress"
    refute_includes ItServices::Transition::ALLOWED.fetch("scheduled"), "awaiting_customer"
    refute_includes ItServices::Transition::ALLOWED.fetch("awaiting_customer"), "in_progress"
  end
end
