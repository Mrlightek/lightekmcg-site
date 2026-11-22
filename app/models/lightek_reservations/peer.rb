require 'digest'
module LightekReservations
  class Peer < ApplicationRecord
    self.table_name = 'lightek_reservation_peers'
    belongs_to :order, class_name: 'LightekCommerce::Order', optional: true
    belongs_to :member_backend, class_name: 'LightekPwa::MemberBackend', optional: true
    validate { errors.add(:order, 'or member backend is required') unless order_id || (has_attribute?(:member_backend_id) && member_backend_id) }
    scope :enabled_installations, -> { where(enabled: true).where.not(order_id: nil) }
    def pwa_only? = order_id.nil?
    belongs_to :merchant, class_name: 'User'
    belongs_to :site, class_name: 'DymondSite::Site'
    has_many :intents, class_name: 'LightekReservations::Intent', dependent: :restrict_with_error
    validates :key, :token_digest, presence: true
    validates :key, uniqueness: true
    def active?
      return enabled? && member_backend && %w[shared_ready migrating dedicated_ready].include?(member_backend.status) if pwa_only?
      enabled? && order.provisioned_at? && order.paid_at? && %w[paid fulfilled].include?(order.status)
    end
    def self.authenticate(token)
      key, secret = token.to_s.split('.', 2)
      return unless secret&.match?(/\A[0-9a-f]{64}\z/) && key&.match?(/\A[0-9a-f-]{36}\z/)
      peer = find_by(key: key)
      return unless peer&.active? && ActiveSupport::SecurityUtils.secure_compare(peer.token_digest, Digest::SHA256.hexdigest(token))
      peer
    end
  end
end
