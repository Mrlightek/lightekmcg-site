# frozen_string_literal: true

module Studio
  module Broadcasting
    class HostedCarriage < ApplicationRecord
      self.table_name = "studio_hosted_carriages"
      belongs_to :peer, class_name: "LightekReservations::Peer"
      belongs_to :fallback_channel, class_name: "Studio::Broadcasting::Channel", optional: true
      delegate :site_id, to: :peer
      validates :key, format: { with: /\A[0-9a-f]{32}\z/ }
      validates :name, length: { in: 1..120 }
      validates :description, length: { maximum: 2000 }
      validates :status, inclusion: { in: %w[requested accepted withdrawn] }
      validates :ownership, inclusion: { in: NetworkCarriage::OWNERSHIPS.keys }, if: -> { status == "accepted" }

      scope :available, -> {
        fresh = where(updated_at: 5.minutes.ago..)
        fresh.or(where.not(fallback_channel_id: nil)).where(status: "accepted", published: true)
      }

      def managed_path = "/gatekeeper/network/#{key}/index.m3u8"
      def measurement_channel_id = -id
    end
  end
end
