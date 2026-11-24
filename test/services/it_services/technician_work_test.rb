require "test_helper"

class ItServicesTechnicianWorkTest < ActiveSupport::TestCase
  test "rejects unauthorized technician before touching work records" do
    assert_raises(ArgumentError) do
      ItServices::TechnicianWork.record!(request: ItServiceRequest.new,
        actor: User.new(role: "client"), step: "diagnosis", result: "passed",
        evidence: "Observed the device's symptoms during a customer session.")
    end
  end

  test "rejects unsupported work step and result" do
    assert_raises(ArgumentError) do
      ItServices::TechnicianWork.record!(request: ItServiceRequest.new,
        actor: User.new(role: "employee"), step: "remote_shell", result: "passed",
        evidence: "A remote command was allegedly executed on a device.")
    end
  end
end
