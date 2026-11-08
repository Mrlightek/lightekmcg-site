module LightekReservations
  class SweepJob < ApplicationJob
    queue_as :default
    def perform
      Reservation.where(status: 'held').find_each do |reservation|
        if reservation.hold_until && reservation.hold_until < Time.current && reservation.order&.status == 'pending_payment'
          LightekCommerce::ReservationExpiryJob.perform_later(reservation.order_id)
        end
        Booking.reconcile!(reservation)
      end
      Reservation.where(status: 'confirmed').where('starts_at <= ?', Time.current).includes(:order).find_each do |reservation|
        if reservation.server? && reservation.paid? && !reservation.order.provisioned_at?
          LightekCommerce::PaidInstanceProvisioningJob.perform_later(reservation.order_id)
        end
      end
      Reservation.where(status: 'confirmed').where('ends_at < ?', 3.days.ago).find_each do |reservation|
        ExpireServerJob.perform_later(reservation.id) if reservation.server?
      end
      Change.where(status: 'awaiting_payment').includes(:order).find_each do |change|
        if change.order.status == 'canceled'
          change.update!(status: 'canceled')
        elsif change.order.paid_at?
          Settlement.for_order!(change.order)
        end
      end
      Change.where(status: %w[scheduled applying]).where('effective_at <= ?', Time.current).find_each do |change|
        PackageChangeJob.perform_later(change.id) unless change.quote['renewal'] && change.order_id.nil?
      end
      Reservation.where(status: 'confirmed').where(starts_at: Time.current..24.hours.from_now).find_each do |reservation|
        NotificationJob.perform_later(reservation.id, "reminder:#{reservation.starts_at.to_i}")
      end
      Reservation.where(status: %w[confirmed checked_in]).where('ends_at < ?', Time.current).find_each do |reservation|
        unless reservation.server?
          reservation.update!(status: 'completed')
          LightekCommerce::Fulfillment.complete!(order: reservation.order, reference: reservation.reference) if reservation.order&.status == 'paid'
        end
      end
    end
  end
end
