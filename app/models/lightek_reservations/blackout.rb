module LightekReservations
  class Blackout < ApplicationRecord
    self.table_name = 'lightek_reservation_blackouts'
    belongs_to :resource, class_name: 'LightekReservations::Resource'
    validates :starts_at, :ends_at, presence: true
    validates :reason, length: {maximum: 300}
    validate { errors.add(:ends_at, 'must follow start') if starts_at && ends_at && ends_at <= starts_at }
  end
end
