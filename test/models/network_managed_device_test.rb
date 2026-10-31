# frozen_string_literal: true
require "test_helper"

class NetworkManagedDeviceTest < ActiveSupport::TestCase
  def attributes
    { name: "Router", identifier: "router-#{SecureRandom.hex(8)}",
      device_type: "router", status: "registered", management_protocol: "snmp" }
  end

  test "registers routers and phones without remote enrollment" do
    router = NetworkManagedDevice.create!(attributes.merge(ip_address: "192.0.2.12"))
    phone = NetworkManagedDevice.create!(attributes.merge(
      identifier: "phone-#{SecureRandom.hex(8)}", device_type: "phone", management_protocol: "mdm"))
    assert_equal "registered", router.status
    assert_equal "phone", phone.device_type
  end

  test "rejects unknown device types and invalid addresses" do
    device = NetworkManagedDevice.new(attributes.merge(device_type: "unknown", ip_address: "not-an-ip"))
    assert_not device.valid?
    assert device.errors[:device_type].any?
    assert device.errors[:ip_address].any?
  end

  test "identifiers are unique" do
    first = NetworkManagedDevice.create!(attributes)
    duplicate = NetworkManagedDevice.new(attributes.merge(identifier: first.identifier))
    assert_not duplicate.valid?
  end
end
