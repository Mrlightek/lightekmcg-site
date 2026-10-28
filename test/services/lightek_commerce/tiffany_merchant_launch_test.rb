require "test_helper"

class TiffanyMerchantLaunchTest < ActiveSupport::TestCase
  test "product variants require positive or zero valid inventory and price" do
    variant = LightekCommerce::ProductVariant.new(name: "Small", price_cents: -1, inventory_quantity: -3)
    refute variant.valid?
    assert variant.errors[:price_cents].present?
    assert variant.errors[:inventory_quantity].present?
  end

  test "variant SKUs remain unique per product" do
    assert LightekCommerce::ProductVariant.reflect_on_association(:product)
    assert LightekCommerce::OrderItem.reflect_on_association(:variant)
  end

  test "native product uploads are supported by Active Storage" do
    assert LightekCommerce::Product.reflect_on_attachment(:photos)
  end
end
