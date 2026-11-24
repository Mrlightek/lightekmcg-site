require "test_helper"

class ItServicesDeviceAssignmentTest < ActiveSupport::TestCase
  test "does not assign a legacy unowned device to a customer" do
    customer = User.new
    request = ItServiceRequest.new(user: customer)
    device = NetworkManagedDevice.new(status: "active")
    actor = User.new(role: "super_admin")
    assert_raises(ArgumentError) { ItServices::DeviceAssignment.call!(request: request, device: device, actor: actor) }
  end

  test "does not allow customer to assign devices" do
    customer = User.new(role: "client")
    request = ItServiceRequest.new(user: customer)
    device = NetworkManagedDevice.new(status: "active")
    assert_raises(ArgumentError) { ItServices::DeviceAssignment.call!(request: request, device: device, actor: customer) }
  end
end
