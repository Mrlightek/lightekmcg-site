# frozen_string_literal: true

module Studio
  module Broadcasting
    class NetworkCarriage < ApplicationRecord
      self.table_name = "studio_network_carriages"
      OWNERSHIPS = { "company" => "Lightek-owned", "affiliate" => "Independent affiliate" }.freeze

      belongs_to :channel, class_name: "Studio::Broadcasting::Channel"
      validates :status, inclusion: { in: %w[requested accepted withdrawn] }
      validates :ownership, inclusion: { in: OWNERSHIPS.keys }, if: -> { status == "accepted" }
      scope :accepted, -> { where(status: "accepted") }

      def self.hub?(site)
        URI.parse(LightekReservations::Federation::Issuer.origin).host == site.host
      end

      def self.visible_channels(site, user:)
        return Channel.none unless hub?(site)
        candidates = Channel.where(id: accepted.select(:channel_id), status: "published", managed_playout: true).includes(:site)
        ids = candidates.select { |channel| playable?(channel, user: user) }.map(&:id)
        Channel.where(id: ids)
      end

      def self.find_visible(site, id, user:)
        raise ActiveRecord::RecordNotFound unless hub?(site)
        channel = Channel.where(id: accepted.select(:channel_id)).find(id)
        raise ActiveRecord::RecordNotFound unless playable?(channel, user: user)

        channel
      end

      def self.playable?(channel, user:)
        return false unless channel.status == "published" && channel.managed_playout?

        # A carriage approval never overrides the originating station's audience policy.
        LightekPwa::Policy.new(user: nil, site: channel.site).authorize!("watch")
        LightekPwa::Policy.new(user: user, site: channel.site).authorize!("watch")
        true
      rescue LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied
        false
      end
    end
  end
end
