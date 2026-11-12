module LightekCommerce
  class SubscriptionEvents
    TYPES = %w[customer.subscription.created customer.subscription.updated customer.subscription.deleted invoice.paid invoice.payment_failed].freeze

    def self.reference(event)
      object = event.data.object.to_h.deep_stringify_keys
      return object["id"] if event.type.start_with?("customer.subscription.")
      value = object["subscription"] || object.dig("parent", "subscription_details", "subscription")
      value.is_a?(Hash) ? value["id"] : value
    end

    def self.metadata(event)
      object = event.data.object.to_h.deep_stringify_keys
      object["metadata"].presence || object.dig("parent", "subscription_details", "metadata") || object["subscription_details"]&.fetch("metadata", {}) || {}
    end

    def self.register!(order:, session:)
      reference = session.subscription.respond_to?(:id) ? session.subscription.id : session.subscription
      raise StripeEvents::Rejected, "Subscription identity missing" if reference.blank?
      Stripe.api_key = DymondBank::StripeCredentials.secret_key
      remote = Stripe::Subscription.retrieve(reference)
      data = remote.to_h.deep_stringify_keys
      expected = PaymentIdentity.metadata(order).stringify_keys
      raise StripeEvents::Rejected, "Subscription order mismatch" unless expected.all? { |key, value| data.fetch("metadata", {})[key] == value }
      item = order.items.sole
      interval = item.purchase_snapshot.fetch("billing_interval")
      remote_item = data.fetch("items").fetch("data").sole
      price = remote_item.fetch("price")
      raise StripeEvents::Rejected, "Subscription price mismatch" unless price["unit_amount"].to_i == item.unit_price_cents &&
        price["currency"] == order.currency && price.dig("recurring", "interval") == interval &&
        price.dig("recurring", "interval_count").to_i == 1 && remote_item["quantity"].to_i == 1
      subscription = Subscription.find_or_initialize_by(order: order)
      if subscription.persisted? && subscription.processor_reference != reference
        raise StripeEvents::Rejected, "Order already has a different subscription"
      end
      subscription.assign_attributes(processor_reference: reference, customer_reference: data["customer"],
        billing_interval: interval, amount_cents: item.unit_price_cents, currency: order.currency)
      apply!(subscription: subscription, data: data)
      subscription
    end

    def self.process!(event)
      reference = reference(event)
      subscription = Subscription.find_by(processor_reference: reference)
      return unless subscription
      # Read the processor's current state so delayed or duplicated events cannot
      # reactivate a canceled subscription or shorten a paid billing period.
      Stripe.api_key = DymondBank::StripeCredentials.secret_key
      data = Stripe::Subscription.retrieve(reference).to_h.deep_stringify_keys
      subscription.with_lock do
        apply!(subscription: subscription, data: data)
        record_invoice!(subscription: subscription, invoice: event.data.object.to_h.deep_stringify_keys, at: Time.at(event.created)) if event.type == "invoice.paid"
      end
      subscription
    end

    def self.record_invoice!(subscription:, invoice:, at:)
      raise StripeEvents::Rejected, "Invoice is not paid" unless invoice["status"] == "paid" && invoice["currency"] == subscription.currency
      record = BillingInvoice.find_or_initialize_by(processor_reference: invoice.fetch("id"))
      return record if record.persisted?
      original = subscription.order
      record.assign_attributes(subscription: subscription, amount_paid_cents: invoice.fetch("amount_paid"),
        currency: invoice.fetch("currency"), paid_at: Time.at(invoice.dig("status_transitions", "paid_at") || at.to_i))
      if invoice["billing_reason"] == "subscription_create"
        record.settlement_order = original
      elsif invoice["billing_reason"] == "subscription_cycle"
        subtotal = invoice["subtotal"].to_i
        tax = invoice["tax"] || Array(invoice["total_taxes"]).sum { |row| row.fetch("amount", 0).to_i }
        # Credits, prorations and multi-payment invoices remain visible receipts
        # for review, rather than creating an incorrect merchant transfer.
        if subtotal.positive? && invoice["total"].to_i == record.amount_paid_cents && subtotal + tax.to_i == record.amount_paid_cents
          renewal = Order.create!(site: original.site, customer_email: original.customer_email, currency: record.currency,
            status: "fulfilled", purpose: "subscription_renewal", stock_reserved: false, revenue_share_snapshot: original.revenue_share_snapshot,
            subtotal_cents: subtotal, tax_cents: tax.to_i, total_cents: record.amount_paid_cents,
            payment_provider: "stripe_invoice", payment_reference: record.processor_reference,
            paid_at: record.paid_at, fulfilled_at: record.paid_at, fulfillment_reference: record.processor_reference)
          source = original.items.sole
          renewal.items.create!(product: source.product, name: source.name, quantity: 1,
            unit_price_cents: subtotal, line_total_cents: subtotal, purchase_snapshot: source.purchase_snapshot)
          RevenueSharing.record!(renewal)
          record.settlement_order = renewal
        end
      end
      record.save!
      record
    end

    def self.apply!(subscription:, data:)
      item = data.fetch("items").fetch("data").first || {}
      period_end = item["current_period_end"] || data["current_period_end"] || subscription.current_period_end&.to_i
      raise StripeEvents::Rejected, "Subscription billing period missing" unless period_end.to_i.positive?
      subscription.assign_attributes(status: data.fetch("status"), cancel_at_period_end: data.fetch("cancel_at_period_end", false), current_period_end: Time.at(period_end.to_i), last_event_at: Time.current)
      subscription.save!
      if subscription.bank_subscription
        subscription.bank_subscription.update!(status: subscription.status, current_period_end: subscription.current_period_end)
      end
      subscription
    end
  end
end
