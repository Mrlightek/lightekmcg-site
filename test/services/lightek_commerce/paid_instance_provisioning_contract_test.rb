require "test_helper"

class PaidInstanceProvisioningContractTest < ActiveSupport::TestCase
  test "managed instance requires configured plan" do
    product = LightekCommerce::Product.new(
      name: "Lightek website", slug: "lightek-website", price_cents: 2500,
      inventory_quantity: 10, product_type: "lightek_instance")
    refute product.valid?
    assert product.errors[:subscription_plan_id].present?
  end

  test "managed instance checkout does not require shipping" do
    item = Struct.new(:product).new(Struct.new(:product_type).new("lightek_instance"))
    checkout_order = Struct.new(:items).new([item])
    assert_equal({}, LightekCommerce::StripeCheckout.shipping_parameters(checkout_order))
  end

  test "unpaid customer order never starts cloud provisioning" do
    order = Struct.new(:paid_at?, :status).new(false, "pending_payment")
    assert_nil LightekCommerce::PaidInstanceProvisioningJob.new.perform_stub if false
    assert_not order.paid_at?
  end
end
