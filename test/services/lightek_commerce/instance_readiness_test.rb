require "test_helper"

class LightekCommerceInstanceReadinessTest < ActiveSupport::TestCase
  test "normal catalog products do not require cloud prerequisites" do
    item = Struct.new(:product).new(Struct.new(:product_type).new("physical"))
    order = Struct.new(:items).new([item])
    assert LightekCommerce::InstanceReadiness.check!(order: order)
  end

  test "installation purchases must contain exactly one unit" do
    product = Struct.new(:product_type).new("lightek_instance")
    item = Struct.new(:product, :quantity).new(product, 2)
    order = Struct.new(:items).new([item])
    assert_raises(LightekCommerce::InstanceReadiness::Unavailable) do
      LightekCommerce::InstanceReadiness.check!(order: order)
    end
  end
end
