# frozen_string_literal: true

module ItServices
  class ReservationAssignment
    def self.call!(request:, reservation:, actor:)
      raise ArgumentError, "Customer authorization required" unless actor&.persisted? &&
        actor.access_active? && actor.id == request.user_id
      raise ArgumentError, "Reservation belongs to another customer" unless reservation.customer_id == request.user_id
      raise ArgumentError, "Reservation is not for a service" unless reservation.resource&.kind == "service"
      raise ArgumentError, "Reservation is cancelled" if reservation.status.in?(%w[canceled expired])
      request.with_lock do
        raise ArgumentError, "Appointment cannot be changed after dispatch" unless request.status.in?(%w[requested triaged])
        raise ArgumentError, "Reservation already belongs to another case" if ItServiceRequest
          .where(reservation_id: reservation.id).where.not(id: request.id).exists?
        request.update!(reservation: reservation)
      end
      request
    end
  end
end
