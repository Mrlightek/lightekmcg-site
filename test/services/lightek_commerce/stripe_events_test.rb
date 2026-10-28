require "test_helper"

class LightekCommerceStripeEventsTest < ActiveSupport::TestCase
  test "ignores unrelated events" do
    event = Struct.new(:type).new("customer.created")
    assert_nil LightekCommerce::StripeEvents.process!(event)
  end
end
