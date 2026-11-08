module LightekReservations
  class ReservationMailer < ApplicationMailer
    def notice(id, reminder: false)
      @reservation = Reservation.includes(resource: :site).find(id)
      @reminder = reminder
      @manage_url = "#{ENV.fetch('LIGHTEK_RESERVATION_ORIGIN', 'https://lightekmcg.com')}/my/reservations/#{id}"
      label = reminder ? 'Upcoming reservation' : "Reservation #{@reservation.status.humanize.downcase}"
      mail(to: @reservation.customer.email_address, subject: "#{@reservation.resource.site.name} · #{label} · #{@reservation.reference}")
    end
  end
end
