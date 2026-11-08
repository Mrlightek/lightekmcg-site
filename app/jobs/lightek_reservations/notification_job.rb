module LightekReservations
  class NotificationJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 5
    def perform(id, key)
      reservation = Reservation.find(id)
      reservation.with_lock do
        return if reservation.notification_keys.include?(key)
        reminder = key.start_with?('reminder:')
        return if reminder && (reservation.status != 'confirmed' || key != "reminder:#{reservation.starts_at.to_i}")
        return if !reminder && key != "#{reservation.status}:#{reservation.starts_at.to_i}"
        ReservationMailer.notice(id, reminder: reminder).deliver_now
        reservation.update_columns(notification_keys: (reservation.notification_keys + [key]).last(100))
      end
    end
  end
end
