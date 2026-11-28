# frozen_string_literal: true
module LightekCommerce
  # Stripe refund events may arrive before or after the API request has returned.
  # Reconcile the recorded processor refund without crediting the same amount twice.
  class RefundSettlement
    def self.call(processor_ref:, status:, return_key: nil, amount_cents: nil)
      record = Refund.find_by(processor_ref: processor_ref)
      if record.nil? && return_key.present?
        record = Refund.where.not(merchandise_return_id: nil).find_by(idempotency_key: return_key, amount_cents: amount_cents)
      end
      return nil unless record
      record.order.with_lock do
        record.reload
        if return_key.present? && (record.merchandise_return_id.nil? || record.idempotency_key != return_key || record.amount_cents != amount_cents)
          return nil
        end
        return nil if record.processor_ref.present? && record.processor_ref != processor_ref
        record.update!(processor_ref: processor_ref) if record.processor_ref.blank?
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
