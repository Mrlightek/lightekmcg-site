# frozen_string_literal: true
require "test_helper"

class DashboardNetworkDeviceManagementTest < ActionDispatch::IntegrationTest
  test "unauthenticated clients cannot register managed devices" do
    identifier = "test-#{SecureRandom.hex(8)}"
    post dashboard_network_devices_path, params: {
      device: { name: "Test router", identifier: identifier, device_type: "router" }
    }
    assert_not NetworkManagedDevice.exists?(identifier: identifier)
  end
end
