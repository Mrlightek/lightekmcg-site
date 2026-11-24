require "test_helper"

class ItServicesTechnicianResponseTest < ActiveSupport::TestCase
  test "rejects unassigned actors" do
    request = ItServiceRequest.new(status: "scheduled", technician_id: 10)
    assert_raises(ArgumentError) do
      ItServices::TechnicianResponse.call!(request: request, actor: User.new(id: 11, role: "employee"),
        decision: "accept", note: "Available")
    end
  end

  test "rejects invalid decisions" do
    assert_raises(ArgumentError) do
      ItServices::TechnicianResponse.call!(request: ItServiceRequest.new, actor: nil,
        decision: "complete", note: "Done")
    end
  end
end
