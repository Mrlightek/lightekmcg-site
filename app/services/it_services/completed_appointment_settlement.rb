module ItServices
  class CompletedAppointmentSettlement
    def self.required?(reservation)
      return false unless reservation && reservation.resource.kind == "service"

      reservation.resource.it_service_appointment? ||
        (Enrollment.operations_ready? && ItServiceRequest.exists?(reservation_id: reservation.id))
    end

    def self.call(request)
      order = request.reservation&.order
      return unless order&.status == "paid" && verified?(request: request, reservation: request.reservation, order: order)

      order.with_lock do
        if Gatekeeper::ItServiceBillingPolicy.funded_order?(order)
          LightekCommerce::Fulfillment.complete!(order: order, reference: "IT service request ##{request.id}", it_service_request: request)
        end
      end
    end

    def self.verified?(request:, reservation:, order:)
      return false unless request&.status == "resolved" && request.technician_id &&
        request.reservation_id == reservation.id && request.user_id == reservation.customer_id &&
        reservation.resource.kind == "service" && reservation.resource.site_id == order.site_id &&
        reservation.status.in?(%w[confirmed checked_in completed])

      ticket = Marlon::Ticket.where(related: request, status: "resolved")
        .where("extra_fields->>'source' = ?", NevaehCustomerService::Cases::SOURCE).order(:id).last
      handoff = ticket&.extra_fields.to_h.fetch("it_services_handoff", {})
      clearance = handoff.fetch("payment_clearance", {})
      handoff.values_at("state", "request_id", "reservation_id", "completed_by_id") ==
        ["customer_confirmed", request.id, reservation.id, request.technician_id] &&
        clearance.values_at("source", "reservation_id", "order_id") ==
          ["lightek_reservations", reservation.id, order.id]
    end

    def self.recover!
      return unless Enrollment.operations_ready?

      paid_appointments = LightekReservations::Reservation.joins(:order)
        .where(lightek_commerce_orders: { status: "paid" }).select(:id)
      ItServiceRequest.where(status: "resolved", reservation_id: paid_appointments).find_each do |request|
        call(request)
      end
    end
  end
end
