require "test_helper"

class LightekCommerceMerchantLaunchTest < ActiveSupport::TestCase
  test "digital products do not require shipping configuration" do
    product = Struct.new(:product_type).new("digital")
    item = Struct.new(:product).new(product)
    order = Struct.new(:items).new([item])
    assert_equal({}, LightekCommerce::StripeCheckout.shipping_parameters(order))
  end

  test "physical goods retain shipping configuration requirement" do
    product = Struct.new(:product_type).new("physical")
    item = Struct.new(:product).new(product)
    order = Struct.new(:items).new([item])
    assert_raises(LightekCommerce::StripeCheckout::Unavailable) do
      original = ENV["LIGHTEK_COMMERCE_STRIPE_SHIPPING_RATE_IDS"]
      begin
        ENV.delete("LIGHTEK_COMMERCE_STRIPE_SHIPPING_RATE_IDS")
        LightekCommerce::StripeCheckout.shipping_parameters(order)
      ensure
        ENV["LIGHTEK_COMMERCE_STRIPE_SHIPPING_RATE_IDS"] = original
      end
    end
  end
end
