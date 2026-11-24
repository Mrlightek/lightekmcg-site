module ItServices
  class AppointmentDispatch
    def self.call!(request:, actor:, note:)
      raise ArgumentError, "Super admin authorization required" unless actor&.role == "super_admin"
      raise ArgumentError, "Dispatch note required" unless note.to_s.strip.length.between?(1, 1500)
      request.with_lock do
        raise ArgumentError, "Request must be triaged" unless request.status.in?(%w[triaged])
        technician = request.technician
        raise ArgumentError, "Active technician assignment required" unless technician&.access_active? &&
          TechnicianAssignment::ELIGIBLE_ROLES.include?(technician.role)
        reservation = request.reservation
        raise ArgumentError, "Service appointment required" unless reservation && reservation.customer_id == request.user_id &&
          reservation.resource&.kind == "service"
        raise ArgumentError, "Appointment must be confirmed" unless reservation.status == "confirmed"
        raise ArgumentError, "Appointment must have a future start time" unless reservation.starts_at&.future?
        payment_receipt = PaymentClearance.verify!(request: request)
        from = request.status
        request.update!(status: "scheduled")
        ItServiceEvent.create!(it_service_request: request, actor: actor, from_status: from, to_status: "scheduled",
          note: "Dispatch confirmed for technician ##{technician.id}, reservation ##{reservation.id}, " \
            "#{reservation.starts_at.utc.iso8601}. #{note.strip}")
        NevaehWorkHandoff.record!(request: request, actor: actor, note: note, payment_receipt: payment_receipt)
      end
      request
    end
  end
end
