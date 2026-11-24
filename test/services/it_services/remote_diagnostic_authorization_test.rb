require "test_helper"

class ItServicesRemoteDiagnosticAuthorizationTest < ActiveSupport::TestCase
  test "refuses unassigned actors before checking devices" do
    request = ItServiceRequest.new(status: "in_progress", delivery_mode: "remote")
    assert_raises(ArgumentError) do
      ItServices::RemoteDiagnosticAuthorization.verify!(request: request, technician: User.new(role: "client"))
    end
  end

  test "refuses inactive appointments before accessing customer devices" do
    technician = User.new(role: "employee")
    def technician.persisted? = true
    def technician.access_active? = true
    request = ItServiceRequest.new(status: "scheduled", delivery_mode: "remote")
    request.technician = technician
    assert_raises(ArgumentError) do
      ItServices::RemoteDiagnosticAuthorization.verify!(request: request, technician: technician)
    end
  end
end
