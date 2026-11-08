require 'digest'
module LightekReservations
  class Peer < ApplicationRecord
    self.table_name = 'lightek_reservation_peers'
    belongs_to :order, class_name: 'LightekCommerce::Order'
    belongs_to :merchant, class_name: 'User'
    belongs_to :site, class_name: 'DymondSite::Site'
    has_many :intents, class_name: 'LightekReservations::Intent', dependent: :restrict_with_error
    validates :key, :token_digest, presence: true
    validates :key, uniqueness: true
    def active?
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
