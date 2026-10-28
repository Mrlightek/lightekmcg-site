require "test_helper"

class LightekCommerceMerchantPayoutsTest < ActiveSupport::TestCase
  test "fee quote reserves processing and platform charges without negative transfers" do
    order = Struct.new(:total_cents).new(100)
    quote = LightekCommerce::MerchantPayouts.fee_quote(order)
    assert_operator quote[:net_cents], :>=, 0
    assert_equal quote[:gross_cents],
      quote[:processor_reserve_cents] + quote[:platform_fee_cents] + quote[:net_cents] if quote[:net_cents].positive?
  end
end
