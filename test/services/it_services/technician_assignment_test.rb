require "test_helper"

class ItServicesTechnicianAssignmentTest < ActiveSupport::TestCase
  test "rejects non-admin assignment" do
    actor = User.new(role: "client")
    request = ItServiceRequest.new(status: "requested")
    assert_raises(ArgumentError) do
      ItServices::TechnicianAssignment.call!(request: request, technician: nil, actor: actor, note: "Assign")
    end
  end

  test "rejects unverified technicians" do
    actor = User.new(role: "super_admin")
    request = ItServiceRequest.new(status: "requested")
    assert_raises(ArgumentError) do
      ItServices::TechnicianAssignment.call!(request: request, technician: nil, actor: actor, note: "Assign")
    end
  end
end
