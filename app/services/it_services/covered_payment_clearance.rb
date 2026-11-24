module ItServices
  module CoveredPaymentClearance
    def verify!(request:)
      reservation = request.reservation
      return super unless reservation && !reservation.order_id && Plan.exists?(resource_id: reservation.resource_id)

      reservation.with_lock do
        unless reservation.customer_id == request.user_id && reservation.status == "confirmed" && reservation.quantity == 1
          raise ArgumentError, "A confirmed, customer-owned Managed IT reservation is required."
        end

        period = Gatekeeper::ItServiceBillingPolicy.coverage!(customer: request.user, resource: reservation.resource,
          starts_at: reservation.starts_at, ends_at: reservation.ends_at)
        raise ArgumentError, "Managed IT coverage is unavailable." unless period

        claim = CoverageClaim.find_or_initialize_by(reservation: reservation)
        if claim.persisted? && claim.service_request_id != request.id
          raise ArgumentError, "This reservation already covers another service request."
        end
        claim.update!(period: period, service_request_id: request.id)
        {
          "source" => "managed_it_subscription", "reservation_id" => reservation.id,
          "coverage_claim_id" => claim.id, "invoice_id" => period.invoice_id,
          "order_id" => period.invoice.settlement_order_id, "paid_at" => period.invoice.paid_at.iso8601(6),
          "verified_at" => Time.current.iso8601(6)
        }
      end
    end
  end
end
