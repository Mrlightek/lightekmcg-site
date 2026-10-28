require "test_helper"

class LightekCommercePaymentReconciliationTest < ActiveSupport::TestCase
  test "duplicate settlement on a partially refunded order does not reset its status" do
    order = LightekCommerce::Order.new(status: "partially_refunded")
    order.define_singleton_method(:with_lock) { |&block| block.call }
    order.define_singleton_method(:site_id) { 1 }
    order.define_singleton_method(:payment_reference) { "cs_test_1" }
    order.define_singleton_method(:currency) { "usd" }
    original = LightekCommerce::Order.method(:find_by)
    LightekCommerce::Order.define_singleton_method(:find_by) { |**_| order }
    session = Struct.new(:metadata, :id, :currency, :mode, :payment_status).new(
      {"lightek_commerce_order_id" => "1", "lightek_site_id" => "1"}, "cs_test_1", "usd", "payment", "paid")
    event = Struct.new(:type, :data).new("checkout.session.completed", Struct.new(:object).new(session))
    assert_equal order, LightekCommerce::StripeEvents.process!(event)
    assert_equal "partially_refunded", order.status
  ensure
    LightekCommerce::Order.define_singleton_method(:find_by, original) if original
  end
end
