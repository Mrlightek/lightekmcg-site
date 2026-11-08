# frozen_string_literal: true
module LightekReservations
  class Reservation < ApplicationRecord
    self.table_name = 'lightek_reservations'
    belongs_to :resource, class_name: 'LightekReservations::Resource'
    belongs_to :customer, class_name: 'User'
    belongs_to :order, class_name: 'LightekCommerce::Order', optional: true
    has_many :package_changes, class_name: 'LightekReservations::Change', dependent: :restrict_with_error
    validates :reference, :checkout_key, :starts_at, :ends_at, :blocks_from, :blocks_until, presence: true
    validates :reference, uniqueness: true
    validates :checkout_key, uniqueness: {scope: :customer_id}
    validates :status, inclusion: {in: %w[held confirmed checked_in completed canceled expired payment_review]}
    validates :quantity, numericality: {only_integer: true, greater_than: 0}
    validates :notes, length: {maximum: 3000}
    validate { errors.add(:ends_at, 'must follow start') if starts_at && ends_at && ends_at <= starts_at }
    after_create_commit :notify_guest
    after_update_commit :notify_guest, if: -> { saved_change_to_status? || saved_change_to_starts_at? }
    def notify_guest
      NotificationJob.perform_later(id, "#{status}:#{starts_at.to_i}")
    end
    scope :occupying, -> {where(status: %w[held confirmed checked_in payment_review])}
    def server? = package_snapshot['kind'] == 'server'
    def paid? = order && order.paid_at? && %w[paid fulfilled].include?(order.status)
    def access_ready? = %w[confirmed checked_in].include?(status) && (!order || paid?)
  end
end
