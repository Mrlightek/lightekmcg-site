require "test_helper"

class ItServicesDeviceHealthSnapshotTest < ActiveSupport::TestCase
  test "denies diagnostics without consent" do
    customer = User.new(id: 101)
    request = ItServiceRequest.new(user: customer)
    assert_raises(ArgumentError) do
      ItServices::DeviceHealthSnapshot.call!(request: request, actor: customer)
    end
  end

  test "denies diagnostics for a different customer" do
    customer = User.new(id: 101)
    outsider = User.new(id: 202)
    request = ItServiceRequest.new(user: customer)
    assert_raises(ArgumentError) do
      ItServices::DeviceHealthSnapshot.call!(request: request, actor: outsider)
    end
  end
end
