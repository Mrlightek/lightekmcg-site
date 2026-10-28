# frozen_string_literal: true
module LightekCommerce
  # Stripe refund events may arrive before or after the API request has returned.
  # Reconcile the recorded processor refund without crediting the same amount twice.
  class RefundSettlement
    def self.call(processor_ref:, status:)
      record = Refund.find_by(processor_ref: processor_ref)
      return nil unless record
      record.order.with_lock do
        record.reload
        return record if record.status == "succeeded"
        case status.to_s
        when "succeeded"
          order = record.order
          new_total = order.refunded_cents + record.amount_cents
          raise ArgumentError, "Refund exceeds order total" if new_total > order.total_cents
          record.update!(status: "succeeded")
          order.update!(refunded_cents: new_total,
            status: new_total == order.total_cents ? "refunded" : "partially_refunded")
        when "failed", "canceled"
          record.update!(status: "failed")
        end
      end
      record
    end
  end
end
