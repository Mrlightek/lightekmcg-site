# frozen_string_literal: true

module ItServices
  # Reuses Reservations checkout and the existing Commerce order payment state.
  # This class never charges a card, creates an invoice, or marks an order paid.
  class PaymentClearance
    def self.verify!(request:)
      reservation = request.reservation
      raise ArgumentError, "Service reservation required" unless reservation &&
        reservation.customer_id == request.user_id && reservation.resource&.kind == "service"
      raise ArgumentError, "Confirmed reservation required" unless reservation.status == "confirmed"
      order = reservation.order
      if order
        raise ArgumentError, "Order does not match customer" unless request.user && order.customer_email.present? &&
          order.customer_email.casecmp?(request.user.email_address.to_s)
        raise ArgumentError, "Paid appointment required" unless reservation.paid?
        raise ArgumentError, "Order must have a recorded payment timestamp" unless order.paid_at.present?
        {
          "source" => "lightek_reservations",
          "reservation_id" => reservation.id,
          "order_id" => order.id,
          "order_status" => order.status,
          "paid_at" => order.paid_at&.iso8601(6),
          "verified_at" => Time.current.iso8601(6)
        }
      else
        # A confirmed reservation alone does not authorize free service.
        # Complimentary/contract-covered work needs a separately auditable
        # authorization policy before dispatch can be enabled.
        raise ArgumentError, "Service checkout required before technician dispatch"
      end
    end
  end
end
