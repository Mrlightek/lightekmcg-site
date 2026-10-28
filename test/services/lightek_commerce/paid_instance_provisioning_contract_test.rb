require "test_helper"

class PaidInstanceProvisioningContractTest < ActiveSupport::TestCase
  test "managed instance requires a configured plan" do
    product = LightekCommerce::Product.new(name: "Lightek website",
      slug: "lightek-website", price_cents: 2500, inventory_quantity: 10,
      product_type: "lightek_instance")
    refute product.valid?
    assert product.errors[:subscription_plan_id].present?
  end

  test "managed instance has no physical shipping charge" do
    item = Struct.new(:product).new(Struct.new(:product_type).new("lightek_instance"))
    order = Struct.new(:items).new([item])
    assert_equal({}, LightekCommerce::StripeCheckout.shipping_parameters(order))
  end

  test "unpaid orders do not invoke customer provisioning" do
    order = Struct.new(:paid_at?, :status).new(false, "pending_payment")
    LightekCommerce::Order.stub(:find, order) do
      LightekCommerce::PaidInstanceProvisioning.stub(:call!, ->(**_) { flunk "Cloud provisioned before payment" }) do
        assert_nil LightekCommerce::PaidInstanceProvisioningJob.new.perform(123)
      end
    end
  end
end
