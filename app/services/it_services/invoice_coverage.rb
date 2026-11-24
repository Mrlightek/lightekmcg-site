module ItServices
  class InvoiceCoverage
    def self.record_checkout!(receipt, order:)
      return unless receipt.subscription.order_id == order.id && Membership.exists?(order_id: order.id)
      unless CoveragePeriod.exists?(invoice: receipt)
        invoice = Stripe::Invoice.retrieve(receipt.processor_reference).to_hash.deep_stringify_keys
        record!(receipt, invoice)
      end
      if CoveragePeriod.exists?(invoice: receipt) && Gatekeeper::ItServiceBillingPolicy.funded_order?(order)
        LightekCommerce::Fulfillment.complete!(order: order, reference: "Managed IT billing receipt ##{receipt.id}")
      end
    end

    def self.record!(receipt, invoice)
      subscription = receipt.subscription
      membership = Membership.find_by(order_id: subscription.order_id)
      return unless membership && receipt.settlement_order && receipt.amount_paid_cents >= subscription.amount_cents
      return unless invoice.values_at("id", "status", "currency", "amount_paid") ==
        [receipt.processor_reference, "paid", receipt.currency, receipt.amount_paid_cents]
      return unless %w[subscription_create subscription_cycle].include?(invoice["billing_reason"])

      lines = invoice.fetch("lines", {})
      items = Array(lines["data"])
      return unless items.one? && !lines["has_more"]

      line = items.first
      details = line.dig("parent", "subscription_item_details") || line
      reference = details["subscription"]
      return unless reference == subscription.processor_reference && details["proration"] == false &&
        line["currency"] == subscription.currency && line["amount"] == subscription.amount_cents

      first, last = line.fetch("period", {}).values_at("start", "end")
      return unless first.is_a?(Integer) && last.is_a?(Integer) && first.positive? && last > first

      membership.coverage_periods.find_or_create_by!(invoice: receipt) do |period|
        period.starts_at = Time.at(first)
        period.ends_at = Time.at(last)
      end
    end
  end
end
