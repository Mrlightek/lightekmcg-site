require "test_helper"

class LightekCommerceStripeWebhookRoutingTest < ActiveSupport::TestCase
  def event(type, metadata)
    session = Struct.new(:metadata).new(metadata)
    Struct.new(:type, :data).new(type, Struct.new(:object).new(session))
  end

  test "commerce checkout dispatches to commerce settlement only" do
    stripe_event = event("checkout.session.completed", { "lightek_commerce_order_id" => "42" })
    calls = []
    LightekCommerce::StripeEvents.stub(:process!, ->(received) { calls << received }) do
      DymondBank::StripeWebhookService.process!(stripe_event)
    end
    assert_equal [stripe_event], calls
  end

  test "unrelated checkout stays with Dymond Bank" do
    stripe_event = event("checkout.session.completed", {})
    LightekCommerce::StripeEvents.stub(:process!, ->(*) { flunk "Commerce called for SUSU event" }) do
      DymondBank::StripeWebhookService.stub(:transaction_for, nil) do
        assert_nil DymondBank::StripeWebhookService.process!(stripe_event)
      end
    end
  end

  test "unrelated Stripe event stays with Dymond Bank" do
    stripe_event = Struct.new(:type).new("customer.created")
    LightekCommerce::StripeEvents.stub(:process!, ->(*) { flunk "Commerce called for unrelated event" }) do
      assert_nil DymondBank::StripeWebhookService.process!(stripe_event)
    end
  end
end
