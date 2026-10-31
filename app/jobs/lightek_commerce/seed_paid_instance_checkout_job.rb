# frozen_string_literal: true

module LightekCommerce
  # Acceptance harness: simulate a settled Stripe checkout through the existing
  # Commerce event processor. The normal processor enqueues provisioning.
  # Never use this to mark a real customer payment as paid.
  class SeedPaidInstanceCheckoutJob < ApplicationJob
    queue_as :default

    def perform(order_id = nil)
      unless Rails.env.test? || (Rails.env.development? && ENV["LIGHTEK_ALLOW_SEEDED_PAYMENT"] == "1")
        raise ArgumentError, "Seeded payment acceptance is restricted to test or explicitly enabled development"
      end

      order = if order_id.present?
        Order.find(order_id)
      else
        Order.where(status: "pending_payment")
          .where("payment_reference LIKE ?", "cs\\_test\\_%")
          .where("subtotal_cents > 0")
          .order(:id)
          .detect do |candidate|
            candidate.items.any? { |item| item.product.product_type == "lightek_instance" }
          end
      end
      raise ArgumentError, "No pending Stripe test instance order exists; create a test checkout first" unless order
      raise ArgumentError, "Order must be pending payment" unless order.status == "pending_payment"
      raise ArgumentError, "Order must contain an instance product" unless order.items.any? { |item| item.product.product_type == "lightek_instance" }
      raise ArgumentError, "Order must have a Stripe test checkout reference" unless order.payment_reference.to_s.start_with?("cs_test_")
      raise ArgumentError, "Order must have a positive amount" unless order.subtotal_cents.to_i.positive?
      raise ArgumentError, "Order must have zero shipping and tax for seeded acceptance" unless order.tax_cents.to_i.zero? && order.shipping_cents.to_i.zero?

      details = Struct.new(:amount_tax, :amount_shipping).new(0, 0)
      session = Struct.new(:metadata, :id, :currency, :mode, :payment_status,
        :amount_subtotal, :total_details, :amount_total).new(
          { "lightek_commerce_order_id" => order.id.to_s, "lightek_site_id" => order.site_id.to_s },
          order.payment_reference, order.currency, "payment", "paid",
          order.subtotal_cents, details, order.subtotal_cents
        )
      event = Struct.new(:type, :data).new("checkout.session.completed", Struct.new(:object).new(session))

      Rails.logger.info("[Commerce] Seeded acceptance payment for test order #{order.id}")
      # Exercise the same routing entrypoint used by the signed webhook after
      # Stripe signature verification; no external payment is represented.
      DymondBank::StripeWebhookService.process!(event)
    end
  end
end
