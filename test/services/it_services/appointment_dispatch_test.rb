require "test_helper"

class ItServicesAppointmentDispatchTest < ActiveSupport::TestCase
  test "rejects non-admin dispatch" do
    request = ItServiceRequest.new(status: "triaged")
    assert_raises(ArgumentError) do
      ItServices::AppointmentDispatch.call!(request: request, actor: User.new(role: "client"), note: "Ready")
    end
  end

  test "requires a meaningful dispatch note" do
    request = ItServiceRequest.new(status: "triaged")
    assert_raises(ArgumentError) do
      ItServices::AppointmentDispatch.call!(request: request, actor: User.new(role: "super_admin"), note: "")
    end
  end
end
