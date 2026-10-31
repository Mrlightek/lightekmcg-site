require "test_helper"

class LightekCommerceStripeEventsTest < ActiveSupport::TestCase
  FakeItem = Struct.new(:product)
  FakeProduct = Struct.new(:product_type)

  class FakeOrder
    attr_reader :id, :site_id, :payment_reference, :currency, :subtotal_cents, :items,
      :status, :paid_at, :tax_cents, :shipping_cents, :total_cents

    def initialize
      @id = 42
      @site_id = 7
      @payment_reference = "cs_test_paid_42"
      @currency = "usd"
      @subtotal_cents = 2500
      @status = "pending_payment"
      @items = [FakeItem.new(FakeProduct.new("lightek_instance"))]
    end

    def with_lock
      yield
    end

    def paid_at?
      !@paid_at.nil?
    end

    def provisioned_at?
      false
    end

    def update!(attrs)
      attrs.each { |key, value| instance_variable_set("@#{key}", value) }
    end
  end

  def checkout_event(order, payment_status: "paid", type: "checkout.session.completed")
    session = Struct.new(:metadata, :id, :currency, :mode, :payment_status,
      :amount_subtotal, :total_details, :amount_total).new(
        {"lightek_commerce_order_id" => order.id.to_s, "lightek_site_id" => order.site_id.to_s},
        order.payment_reference, "usd", "payment", payment_status, 2500,
        Struct.new(:amount_tax, :amount_shipping).new(0, 0), 2500)
    Struct.new(:type, :data).new(type, Struct.new(:object).new(session))
  end

  test "ignores unrelated events" do
    event = Struct.new(:type).new("customer.created")
    assert_nil LightekCommerce::StripeEvents.process!(event)
  end

  test "settled checkout marks instance order paid and queues exactly one provisioning job" do
    order = FakeOrder.new
    queued = []
    confirmations = []
    LightekCommerce::Order.stub(:find_by, order) do
      LightekCommerce::OrderConfirmationJob.stub(:perform_later, ->(id) { confirmations << id }) do
        LightekCommerce::PaidInstanceProvisioningJob.stub(:perform_later, ->(id) { queued << id }) do
          assert_same order, LightekCommerce::StripeEvents.process!(checkout_event(order))
        end
      end
    end
    assert_equal "paid", order.status
    assert order.paid_at?
    assert_equal [42], confirmations
    assert_equal [42], queued
  end

  test "unsettled checkout never queues provisioning" do
    order = FakeOrder.new
    LightekCommerce::Order.stub(:find_by, order) do
      LightekCommerce::PaidInstanceProvisioningJob.stub(:perform_later, ->(*) { flunk "unpaid instance queued" }) do
        assert_same order, LightekCommerce::StripeEvents.process!(checkout_event(order, payment_status: "unpaid"))
      end
    end
    assert_equal "pending_payment", order.status
    refute order.paid_at?
  end

  test "replayed paid event retries unprovisioned order rather than charging or marking it again" do
    order = FakeOrder.new
    order.update!(status: "paid", paid_at: Time.current)
    queued = []
    LightekCommerce::Order.stub(:find_by, order) do
      LightekCommerce::PaidInstanceProvisioningJob.stub(:perform_later, ->(id) { queued << id }) do
        assert_same order, LightekCommerce::StripeEvents.process!(checkout_event(order))
      end
    end
    assert_equal [42], queued
  end

  test "mismatched checkout identity is rejected before settlement" do
    order = FakeOrder.new
    event = checkout_event(order)
    event.data.object.id = "cs_other"
    LightekCommerce::Order.stub(:find_by, order) do
      LightekCommerce::PaidInstanceProvisioningJob.stub(:perform_later, ->(*) { flunk "invalid checkout queued" }) do
        assert_raises(LightekCommerce::StripeEvents::Rejected) do
          LightekCommerce::StripeEvents.process!(event)
        end
      end
    end
    refute order.paid_at?
  end
end
