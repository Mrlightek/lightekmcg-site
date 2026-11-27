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
      fee = order.buyer_fee_cents
      expected_amounts = [item.unit_price_cents]
      expected_amounts << fee if fee.positive?
      remote_items = data.fetch('items')
      valid_prices = remote_items.fetch('data').map do |remote_item|
        price = remote_item.fetch('price')
        unless price['currency'] == order.currency && price.dig('recurring', 'interval') == interval &&
            price.dig('recurring', 'interval_count').to_i == 1 && remote_item['quantity'].to_i == 1
          raise StripeEvents::Rejected, 'Subscription price mismatch'
        end

        price.fetch('unit_amount').to_i
      end
      if remote_items['has_more'] || valid_prices.sort != expected_amounts.sort
        raise StripeEvents::Rejected, 'Subscription price mismatch'
      end
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
      if event.type == "invoice.paid" && defined?(LightekCommunications::VoiceProvisioningJob)
        LightekCommunications::VoiceProvisioningJob.enqueue_paid!(subscription.order)
      end
      if event.type == "invoice.paid" && defined?(LightekCommunications::CellularBundleJob)
        LightekCommunications::CellularBundleJob.enqueue_paid!(subscription.order)
      end
      if event.type == "invoice.paid" && defined?(LightekCommunications::FullPackageJob)
        order = subscription.order
        LightekCommunications::FullPackageJob.enqueue!(order) if order.provisioned_at?
      end
      subscription
    end

    def self.record_invoice!(subscription:, invoice:, at:)
      raise StripeEvents::Rejected, "Invoice is not paid" unless invoice["status"] == "paid" && invoice["currency"] == subscription.currency
      record = BillingInvoice.find_or_initialize_by(processor_reference: invoice.fetch("id"))
      if record.persisted?
        LightekPwa::CreatorSupport.record!(order: record.settlement_order, original_order: subscription.order) if defined?(LightekPwa::CreatorSupport) && record.settlement_order
        settle_agency_renewal!(subscription, invoice, record)
        return record
      end
      original = subscription.order
      record.assign_attributes(subscription: subscription, amount_paid_cents: invoice.fetch("amount_paid"),
        currency: invoice.fetch("currency"), paid_at: Time.at(invoice.dig("status_transitions", "paid_at") || at.to_i))
      if invoice["billing_reason"] == "subscription_create"
        record.settlement_order = original
      elsif invoice["billing_reason"] == "subscription_cycle"
        invoice_subtotal = invoice['subtotal'].to_i
        buyer_fee = original.buyer_fee_breakdown
        buyer_fee_cents = original.buyer_fee_cents
        subtotal = invoice_subtotal - buyer_fee_cents
        tax = invoice["tax"] || Array(invoice["total_taxes"]).sum { |row| row.fetch("amount", 0).to_i }
        # Credits, prorations and multi-payment invoices remain visible receipts
        # for review, rather than creating an incorrect merchant transfer.
        exact_buyer_price = buyer_fee.empty? || (subtotal == original.subtotal_cents &&
          currency_amounts_match?(invoice, subscription, original))
        if exact_buyer_price && subtotal.positive? && invoice["total"].to_i == record.amount_paid_cents &&
            invoice_subtotal + tax.to_i == record.amount_paid_cents
          renewal = Order.create!(site: original.site, customer_email: original.customer_email, currency: record.currency,
            status: "fulfilled", purpose: renewal_purpose(original), stock_reserved: false, revenue_share_snapshot: original.revenue_share_snapshot,
            buyer_fee_snapshot: buyer_fee, subtotal_cents: subtotal, tax_cents: tax.to_i, total_cents: record.amount_paid_cents,
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
      settle_agency_renewal!(subscription, invoice, record)
      LightekPwa::CreatorSupport.record!(order: record.settlement_order, original_order: original) if defined?(LightekPwa::CreatorSupport) && record.settlement_order
      LightekPwa::RevenueEligibility.record!(subscription: subscription, reference: "invoice:#{record.processor_reference}") if defined?(LightekPwa::RevenueEligibility)
      record
    end

    def self.currency_amounts_match?(invoice, subscription, order)
      lines = invoice.fetch('lines', {})
      return false if lines['has_more']

      expected = [subscription.amount_cents, order.buyer_fee_cents]
      rows = Array(lines['data'])
      rows.size == expected.size && rows.all? { |line|
        line['currency'] == order.currency && line['quantity'].to_i == 1 && !line['proration'] &&
          !line.dig('parent', 'subscription_item_details', 'proration')
      } && rows.map { |line| line['amount'].to_i }.sort == expected.sort
    end
    private_class_method :currency_amounts_match?

    def self.renewal_purpose(order)
      case order.purpose
      when "creator_support" then "creator_support_renewal"
      when "agency_membership" then "agency_membership"
      else "subscription_renewal"
      end
    end
    private_class_method :renewal_purpose

    def self.settle_agency_renewal!(subscription, invoice, receipt)
      return unless invoice["billing_reason"] == "subscription_cycle" && subscription.order.purpose == "agency_membership"

      LightekAgency::Trial.settle!(order: subscription.order, receipt: receipt)
    end
    private_class_method :settle_agency_renewal!

    def self.apply!(subscription:, data:)
      items = data.fetch('items').fetch('data')
      item = items.find { |row| row.dig('price', 'unit_amount').to_i == subscription.amount_cents } || items.first || {}
      period_end = item["current_period_end"] || data["current_period_end"] || subscription.current_period_end&.to_i
      raise StripeEvents::Rejected, "Subscription billing period missing" unless period_end.to_i.positive?
      period_start = item['current_period_start'] || data['current_period_start']
      subscription.current_period_start = Time.at(period_start.to_i) if period_start.to_i.positive?
      subscription.assign_attributes(status: data.fetch("status"), cancel_at_period_end: data.fetch("cancel_at_period_end", false), current_period_end: Time.at(period_end.to_i), last_event_at: Time.current)
      subscription.save!
      if subscription.bank_subscription
        subscription.bank_subscription.update!(status: subscription.status, current_period_end: subscription.current_period_end)
      end
      subscription
    end
  end
end
