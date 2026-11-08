module LightekReservations
  class Change < ApplicationRecord
    self.table_name = 'lightek_reservation_changes'
    belongs_to :reservation, class_name: 'LightekReservations::Reservation'
    belongs_to :target_resource, class_name: 'LightekReservations::Resource'
    belongs_to :order, class_name: 'LightekCommerce::Order', optional: true
    validates :status, inclusion: {in: %w[quoted awaiting_payment scheduled applying applied canceled failed]}
    validates :amount_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  end
end
