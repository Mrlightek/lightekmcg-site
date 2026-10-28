require "test_helper"
class LightekCommerceFulfillmentTest < ActiveSupport::TestCase
  test "cannot fulfill an unpaid order" do
    order = LightekCommerce::Order.new(status: "pending_payment")
    assert_raises(LightekCommerce::Fulfillment::Invalid) do
      LightekCommerce::Fulfillment.complete!(order: order, reference: nil)
    end
  end
end
