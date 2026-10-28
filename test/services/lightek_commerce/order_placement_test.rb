require "test_helper"
class LightekCommerceOrderPlacementTest < ActiveSupport::TestCase
  test "empty cart cannot become an order" do
    assert_raises(LightekCommerce::OrderPlacement::Invalid) do
      LightekCommerce::OrderPlacement.call(site: nil, customer_email: "example@example.com", quantities: {})
    end
  end
end
