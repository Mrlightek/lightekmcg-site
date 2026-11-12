module LightekCommerce
  class ProcessorPayment
    def self.intent!(order:)
      if order.payment_provider == "stripe_invoice"
        invoice_id = order.payment_reference
      else
        session = Stripe::Checkout::Session.retrieve(order.payment_reference).to_h.deep_stringify_keys
        return identifier(session["payment_intent"]) if session["payment_intent"].present?
        invoice_id = identifier(session["invoice"])
      end
      raise Refunds::Invalid, "Payment invoice missing" if invoice_id.blank?
      invoice = Stripe::Invoice.retrieve(invoice_id).to_h.deep_stringify_keys
      reference = identifier(invoice["payment_intent"])
      unless reference
        payments = Array(invoice.dig("payments", "data")).select { |payment| payment["status"] == "paid" && payment.dig("payment", "type") == "payment_intent" }
        raise Refunds::Invalid, "Multiple invoice payments require manual refund review" unless payments.one? && !invoice.dig("payments", "has_more")
        reference = identifier(payments.sole.dig("payment", "payment_intent"))
      end
      raise Refunds::Invalid, "Payment intent missing" unless reference.to_s.start_with?("pi_")
      reference
    end
    def self.identifier(value) = value.is_a?(Hash) ? value["id"] : value
  end
end
