require "test_helper"

class LightekCommerceReleaseContractsTest < ActiveSupport::TestCase
  test "unpaid orders cannot be fulfilled" do
    order = LightekCommerce::Order.new(status: "pending_payment")
    assert_raises(LightekCommerce::Fulfillment::Invalid) do
      LightekCommerce::Fulfillment.complete!(order: order, reference: "tracking")
    end
  end

  test "unrelated processor events do not settle an order" do
    event = Struct.new(:type).new("customer.created")
    assert_nil LightekCommerce::StripeEvents.process!(event)
  end

  test "empty carts cannot reserve inventory" do
    assert_raises(LightekCommerce::OrderPlacement::Invalid) do
      LightekCommerce::OrderPlacement.call(site: nil, customer_email: "buyer@example.com", quantities: {})
    end
  end

  test "commerce states distinguish payment fulfillment cancellation and refund" do
    assert_includes LightekCommerce::Order::STATUSES, "pending_payment"
    assert_includes LightekCommerce::Order::STATUSES, "paid"
    assert_includes LightekCommerce::Order::STATUSES, "fulfilled"
    assert_includes LightekCommerce::Order::STATUSES, "partially_refunded"
    assert_includes LightekCommerce::Order::STATUSES, "refunded"
  end
end
