module LightekReservations
  class Intent < ApplicationRecord
    self.table_name = 'lightek_reservation_intents'
    belongs_to :peer, class_name: 'LightekReservations::Peer'
    belongs_to :resource, class_name: 'LightekReservations::Resource'
    belongs_to :reservation, class_name: 'LightekReservations::Reservation', optional: true
    belongs_to :customer, class_name: 'User', optional: true
    validates :token, :checkout_key, :remote_subject, :expires_at, :starts_at, presence: true
    validates :remote_subject, format: {with: /\A[a-zA-Z0-9_-]{1,64}\z/}
    validates :checkout_key, format: {with: /\A[0-9a-f-]{36}\z/i}, uniqueness: {scope: :peer_id}
  end
end
