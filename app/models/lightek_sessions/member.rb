module LightekSessions
  class Member < ApplicationRecord
    self.table_name = 'lightek_session_members'
    belongs_to :room, class_name: 'LightekSessions::Room'
    belongs_to :user
    belongs_to :reservation, class_name: 'LightekReservations::Reservation', optional: true
    validates :status, inclusion: {in: %w[waiting admitted blocked]}
  end
end
