# frozen_string_literal: true
module LightekMarketplace
  module CheckoutSettlement
    def purchase(offer:, customer:, interval: nil, linked_account: nil, memo: nil)
      return super unless offer && [88, 89].include?(offer.meta.to_h.dig("lightek_marketplace", "version"))
      return {ok: false, error: "Offer is unavailable"} unless offer.active?
      return {ok: false, error: "Customer is required"} unless customer&.persisted?
      iv = (interval.presence || offer.default_interval).to_s
      return {ok: false, error: "Invalid billing interval"} unless Array(offer.available_intervals).include?(iv)
      if linked_account && (!linked_account.active? || linked_account.linkable != customer)
        return {ok: false, error: "Payment account does not belong to this customer"}
      end
      due = offer.due_today_cents(iv).to_i
      return {ok: false, error: "Invalid checkout amount"} if due.negative?
      order = nil
      ActiveRecord::Base.transaction do
        # Both setup and the first billing period belong on the invoice that
        # the existing Bank payment screen will collect. Trials defer recurring.
        items = []
        unless offer.free? || offer.demo?
          items << {description: "#{offer.name} — setup", quantity: 1,
            unit_price_cents: offer.setup_fee_cents.to_i} if offer.setup_fee?
          if offer.recurring? && !offer.trial? && offer.recurring_cents_for(iv).to_i.positive?
            items << {description: "#{offer.name} — first #{iv == 'annual' ? 'year' : 'month'}",
              quantity: 1, unit_price_cents: offer.recurring_cents_for(iv).to_i}
          end
        end
        invoice = if due.positive?
          DymondBank::BillingService.create_project_invoice(billable: customer, line_items: items,
            linked_account: linked_account, due_in_days: 0, memo: memo.presence || "Offer: #{offer.slug}")
        end
        if invoice && (invoice.total_cents.to_i != due || invoice.currency.to_s.upcase != offer.currency.to_s.upcase)
          raise ArgumentError, "Invoice does not match the quoted amount and currency"
        end
        sub = if offer.recurring? && !offer.free? && !offer.demo?
          trial_days = offer.effective_trial_days
          starts = Time.current
          DymondBank::Subscription.create!(subscriber: customer, plan: offer.subscription_plan,
            linked_account: linked_account, billing_interval: iv,
            status: due.positive? ? "unpaid" : (trial_days.positive? ? "trialing" : "active"),
            trial_ends_at: trial_days.positive? ? starts + trial_days.days : nil,
            current_period_start: starts,
            current_period_end: trial_days.positive? ? starts + trial_days.days : (iv == "annual" ? starts + 1.year : starts + 1.month))
        end
        order = DymondBank::Purchase.create!(offer: offer, customer: customer, invoice: invoice,
          subscription: sub, status: "pending", mode: offer.mode, billing_interval: iv,
          amount_cents: due, currency: offer.currency, provision_spec: provision_spec(offer, customer))
      end
      # Keep the existing dispatch order history; never turn a queue failure into
      # a false checkout failure after the invoice/order have already committed.
      begin
        wi = open_order_work_item(order)
        order.update!(work_item_id: wi.id)
      rescue StandardError => e
        order.update!(error: "Order history enqueue failed: #{e.class.name}" )
        Rails.logger.error("[Marketplace] Order history enqueue failed purchase=#{order.id} class=#{e.class.name}")
      end
      order.mark_paid! if due.zero?
      {ok: true, offer: offer, purchase: order, invoice: order.invoice,
        subscription: order.subscription, due_today_cents: due, provision: order.provision_spec}
    rescue StandardError => e
      # A committed order must remain discoverable; it must not invite an
      # accidental second purchase merely because post-commit delivery failed.
      if order&.persisted?
        Rails.logger.error("[Marketplace] Post-checkout handoff failed purchase=#{order.id} class=#{e.class.name}")
        return {ok: true, offer: offer, purchase: order, invoice: order.invoice,
          subscription: order.subscription, due_today_cents: due, provision: order.provision_spec,
          fulfillment_pending: true}
      end
      {ok: false, error: e.message, offer: offer}
    end
  end

end
