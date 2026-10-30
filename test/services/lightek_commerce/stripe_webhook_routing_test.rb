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

  test "async paid Commerce checkout dispatches to Commerce" do
    stripe_event = event("checkout.session.async_payment_succeeded", { "lightek_commerce_order_id" => "42" })
    received = []
    LightekCommerce::StripeEvents.stub(:process!, ->(value) { received << value }) do
      DymondBank::StripeWebhookService.process!(stripe_event)
    end
    assert_equal [stripe_event], received
  end

  test "expired Commerce checkout dispatches to Commerce" do
    stripe_event = event("checkout.session.expired", { "lightek_commerce_order_id" => "42" })
    received = []
    LightekCommerce::StripeEvents.stub(:process!, ->(value) { received << value }) do
      DymondBank::StripeWebhookService.process!(stripe_event)
    end
    assert_equal [stripe_event], received
  end

  test "unrelated checkout stays with Dymond Bank" do
    stripe_event = event("checkout.session.completed", {})
    LightekCommerce::StripeEvents.stub(:process!, ->(*) { flunk "Commerce called for SUSU event" }) do
      DymondBank::StripeWebhookService.stub(:transaction_for, nil) do
        assert_nil DymondBank::StripeWebhookService.process!(stripe_event)
      end
    end
  end

  test "SUSU paid checkout retains existing Dymond Bank settlement" do
    stripe_event = event("checkout.session.completed", {})
    stripe_event.data.object.define_singleton_method(:payment_status) { "paid" }
    transaction = Object.new
    settled = []
    LightekCommerce::StripeEvents.stub(:process!, ->(*) { flunk "Commerce intercepted SUSU payment" }) do
      DymondBank::StripeWebhookService.stub(:transaction_for, transaction) do
        DymondBank::BillingService.stub(:succeed_transaction!, ->(txn) { settled << txn }) do
          DymondBank::StripeWebhookService.process!(stripe_event)
        end
      end
    end
    assert_equal [transaction], settled
  end

  test "unrelated Stripe event stays with Dymond Bank" do
    stripe_event = Struct.new(:type).new("customer.created")
    LightekCommerce::StripeEvents.stub(:process!, ->(*) { flunk "Commerce called for unrelated event" }) do
      assert_nil DymondBank::StripeWebhookService.process!(stripe_event)
    end
  end
end
