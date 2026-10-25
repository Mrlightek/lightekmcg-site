# frozen_string_literal: true
require_relative "marketplace_acceptance_test"
require "ostruct"

class MarketplaceCheckoutSettlementTest < ActiveSupport::TestCase
  include MarketplaceTestData
  self.use_transactional_tests = true

  def with_order_dispatch(fail: false)
    dispatch = DymondDispatch::Dispatch
    original = dispatch.method(:open)
    dispatch.define_singleton_method(:open) do |**_args|
      raise "queue unavailable" if fail
      Struct.new(:id).new(nil)
    end
    yield
  ensure
    dispatch.define_singleton_method(:open, original) if original
  end

  def checkout(overrides = {}, interval: "monthly", **keyword_overrides)
    overrides = overrides.merge(keyword_overrides)
    listing = create_marketplace_product({billing: "both", monthly_price: "29", annual_price: "290", setup_fee: "5"}.merge(overrides))
    result = nil
    with_order_dispatch do
      result = DymondBank::Checkout.purchase(offer: listing.offer, customer: marketplace_actor("client"), interval: interval)
    end
    assert result[:ok], result[:error]
    result.fetch(:purchase)
  end

  def assert_manual_delivery(order)
    order.reload
    assert_equal "provisioning", order.status
    receipt = order.provision_spec.fetch("marketplace_delivery")
    assert_equal "work_requested", receipt.fetch("stage")
    ticket = Marlon::Ticket.find(receipt.fetch("ticket_id"))
    assert_equal order.id, ticket.related_id
    assert_equal order.class.base_class.name, ticket.related_type
  end

  def payment_transaction(order)
    DymondBank::Transaction.create!(invoice: order.invoice, transaction_type: "charge", status: "pending",
      currency: order.currency, amount_cents: order.amount_cents, fee_cents: 0, net_cents: order.amount_cents,
      processor_name: "stripe", processor_ref: "cs_test_#{SecureRandom.hex(8)}", idempotency_key: SecureRandom.uuid)
  end

  def settle(order, payment_status: "paid", type: "checkout.session.completed")
    txn = payment_transaction(order)
    session = OpenStruct.new(id: txn.processor_ref, metadata: OpenStruct.new(dymond_transaction_id: txn.id), payment_status: payment_status)
    event = OpenStruct.new(type: type, data: OpenStruct.new(object: session))
    yield event, txn if block_given?
    DymondBank::StripeWebhookService.process!(event)
    [event, txn]
  end

  test "monthly invoice includes setup and first month" do
    order = checkout
    assert_equal 3400, order.amount_cents
    assert_equal 3400, order.invoice.total_cents
    assert_equal [500,2900], order.invoice.line_items.order(:id).pluck(:unit_price_cents)
    assert_equal "pending", order.status
    assert_equal "unpaid", order.subscription.status
  end

  test "yearly invoice includes first year and annual service period" do
    order = checkout({}, interval: "annual")
    assert_equal 29500, order.invoice.total_cents
    assert_equal "annual", order.subscription.billing_interval
    settle(order)
    assert_equal "active", order.subscription.reload.status
    assert_in_delta 1.year.from_now.to_i, order.subscription.current_period_end.to_i, 5
  end

  test "paid plan without setup still has a collectable invoice" do
    order = checkout(setup_fee: "0")
    assert_equal 2900, order.invoice.total_cents
    assert_equal 2900, order.invoice.amount_remaining_cents
  end

  test "a paid trial setup does not charge first recurring period" do
    order = checkout(trial_days: 14)
    assert_equal 500, order.invoice.total_cents
    assert_equal "unpaid", order.subscription.status
    settle(order)
    assert_equal "trialing", order.subscription.reload.status
    assert_in_delta 14.days.from_now.to_i, order.subscription.trial_ends_at.to_i, 5
  end

  test "zero due trial has no invoice and can start immediately" do
    order = checkout(setup_fee: "0", trial_days: 14)
    assert_nil order.invoice
    assert_manual_delivery(order)
    assert_equal "trialing", order.subscription.status
  end

  test "free and one time products produce the intended billing artifacts" do
    free = checkout(billing: "free", setup_fee: "0")
    assert_nil free.invoice
    assert_nil free.subscription
    assert_manual_delivery(free)
    once = checkout(billing: "once", price: "40", setup_fee: "5")
    assert_equal 4500, once.invoice.total_cents
    assert_nil once.subscription
  end

  test "unpaid invoice cannot activate subscription or announce paid purchase" do
    order = checkout
    assert_raises(LightekMarketplace::PaidPurchaseSettlement::PaymentNotReady) { order.mark_paid! }
    settle(order, payment_status: "unpaid")
    assert_equal "pending", order.reload.status
    assert_equal "unpaid", order.subscription.reload.status
  end

  test "successful payment announces paid once across duplicate events" do
    order = checkout
    count = 0
    listener = ActiveSupport::Notifications.subscribe("dymond_bank.purchase.paid") { count += 1 }
    begin
      event, _txn = settle(order)
      DymondBank::StripeWebhookService.process!(event)
      order.reload.mark_paid!
      assert_equal 1, count
      assert_manual_delivery(order)
      assert_equal "active", order.subscription.reload.status
    ensure
      ActiveSupport::Notifications.unsubscribe(listener)
    end
  end

  test "failed payment leaves order and subscription unfulfilled" do
    order = checkout
    settle(order, type: "checkout.session.async_payment_failed")
    assert_equal "pending", order.reload.status
    assert_equal "unpaid", order.subscription.reload.status
    refute order.invoice.reload.paid?
  end

  test "partial wrong owner or wrong currency invoice cannot fulfill order" do
    order = checkout
    order.invoice.update!(status: "paid", amount_remaining_cents: 100)
    assert_raises(LightekMarketplace::PaidPurchaseSettlement::PaymentNotReady) { order.mark_paid! }
    order.invoice.update!(amount_remaining_cents: 0, currency: "EUR")
    assert_raises(LightekMarketplace::PaidPurchaseSettlement::PaymentNotReady) { order.mark_paid! }
    order.invoice.update!(currency: "USD", billable: marketplace_actor("client"))
    assert_raises(LightekMarketplace::PaidPurchaseSettlement::PaymentNotReady) { order.mark_paid! }
  end

  test "cancelled orders cannot be revived by a later payment event" do
    order = checkout
    order.update!(status: "cancelled")
    settle(order)
    assert_equal "cancelled", order.reload.status
    assert order.invoice.reload.paid?
  end

  test "invalid billing interval creates no billing records" do
    listing = create_marketplace_product
    assert_no_difference ["DymondBank::Purchase.count", "DymondBank::Invoice.count", "DymondBank::Subscription.count"] do
      result = DymondBank::Checkout.purchase(offer: listing.offer, customer: marketplace_actor("client"), interval: "bogus")
      refute result[:ok]
    end
  end

  test "dispatch outage retains one committed order and returns it for payment" do
    listing = create_marketplace_product
    with_order_dispatch(fail: true) do
      assert_difference "DymondBank::Purchase.count", 1 do
        result = DymondBank::Checkout.purchase(offer: listing.offer, customer: marketplace_actor("client"))
        assert result[:ok]
        assert result[:invoice]
        assert_includes result[:purchase].error, "enqueue failed"
      end
    end
  end
  test "a partial or wrong currency transaction cannot settle the order invoice" do
    order = checkout
    txn = payment_transaction(order)
    txn.update!(amount_cents: 1)
    assert_raises(ArgumentError) { DymondBank::BillingService.succeed_transaction!(txn) }
    txn.update!(amount_cents: order.amount_cents, currency: "EUR")
    assert_raises(ArgumentError) { DymondBank::BillingService.succeed_transaction!(txn) }
    refute order.invoice.reload.paid?
    assert_equal "pending", order.reload.status
  end

  test "subscription canceled before settlement stays canceled while money is recorded" do
    order = checkout
    order.subscription.cancel!
    settle(order)
    assert order.invoice.reload.paid?
    assert_equal "canceled", order.subscription.reload.status
    assert_equal "pending", order.reload.status
    assert_includes order.error, "delivery stopped"
  end

  test "settled manual order creates one work request through repeated payment handoff" do
    order = checkout
    assert_difference "Marlon::Ticket.count", 1 do
      event, _txn = settle(order)
      DymondBank::StripeWebhookService.process!(event)
      Marlon::Provisioning.fulfill(order.reload)
    end
    assert_manual_delivery(order)
  end

  test "website records do not count as a deployed website" do
    order = checkout(delivery: "website")
    assert_difference "DymondSite::Site.count", 1 do
      settle(order)
      LightekMarketplace::Delivery.call(order.reload)
      LightekMarketplace::Delivery.call(order.reload)
    end
    assert_equal "provisioning", order.reload.status
    assert_equal true, order.provision_spec.dig("marketplace_delivery", "activation_required")
    refute order.provisioned?
  end

end
