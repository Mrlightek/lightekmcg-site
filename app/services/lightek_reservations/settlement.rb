module LightekReservations
  module Settlement
    module_function
    def complete_appointment!(reservation)
      return unless reservation.order&.status == "paid"
      return if defined?(ItServices::CompletedAppointmentSettlement) && ItServices::CompletedAppointmentSettlement.required?(reservation)

      LightekCommerce::Fulfillment.complete!(order: reservation.order, reference: reservation.reference)
    end

    def for_order!(order)
      if (reservation = Reservation.find_by(order_id: order.id))
        Booking.reconcile!(reservation)
        if reservation.server? && reservation.status == 'confirmed' && !order.provisioned_at?
          LightekCommerce::PaidInstanceProvisioningJob.set(wait_until: [reservation.starts_at, Time.current].max).perform_later(order.id)
        end
      end
      if (change = Change.find_by(order_id: order.id)) && order.paid_at? && %w[paid fulfilled].include?(order.status)
        change.with_lock do
          change.update!(status: 'scheduled') if change.status == 'awaiting_payment'
        end
      end
    end
  end
end
