require "test_helper"

class ItServiceRequestTest < ActiveSupport::TestCase
  test "service and delivery mode must be supported" do
    request = ItServiceRequest.new(service_code: "unknown", delivery_mode: "unattended", description: "Computer is slow")
    assert_not request.valid?
    assert_includes request.errors.attribute_names, :service_code
    assert_includes request.errors.attribute_names, :delivery_mode
  end

  test "onsite support requires location" do
    request = ItServiceRequest.new(service_code: "computer_repair", delivery_mode: "onsite", description: "Won't boot")
    assert_not request.valid?
    assert_includes request.errors.attribute_names, :service_location
  end

  test "remote support does not require a location" do
    request = ItServiceRequest.new(service_code: "optimization", delivery_mode: "remote", description: "Slow startup")
    request.valid?
    assert_not_includes request.errors.attribute_names, :service_location
  end

  test "request requires an owner" do
    request = ItServiceRequest.new(service_code: "optimization", delivery_mode: "remote", description: "Slow startup")
    request.valid?
    assert_includes request.errors.attribute_names, :user
  end
end
