require "test_helper"

class LightekCommerceRefundSettlementTest < ActiveSupport::TestCase
  test "unknown refund does not affect orders" do
    assert_nil LightekCommerce::RefundSettlement.call(processor_ref: "re_unknown", status: "succeeded")
  end
end
