# frozen_string_literal: true

module Studio
  module Advertising
    class Placement < ApplicationRecord
      self.table_name = "studio_ad_placements"

      belongs_to :campaign, class_name: "Studio::Advertising::Campaign"
      belongs_to :station_site, class_name: "DymondSite::Site"
      belongs_to :producer, class_name: "::User", optional: true
      belongs_to :airing, class_name: "Studio::Broadcasting::Airing", optional: true
      belongs_to :peer, class_name: "LightekReservations::Peer", optional: true

      def locally_exchanged? = exchange_key.present? && !peer_id?

      def payable_airing?
        return remote_state == "published" && !remote_retired? if peer_id?

        airing && airing.channel.managed_playout? && airing.channel.status == "published" &&
          airing.status.in?(Studio::Broadcasting::Airing::ACTIVE)
      end

      def booked_start = peer_id? ? scheduled_start : airing&.starts_at

      def authorized_for?(ends_at)
        if locally_exchanged?
          remote_state == "authorized" && remote_authorized_until && remote_authorized_until > ends_at + 10.minutes
        else
          payment&.ready_at?(ends_at)
        end
      end

      has_one :payment, class_name: "Studio::Advertising::Payment", dependent: :restrict_with_error

      def finished_without_delivery?
        return !delivered_at? && (remote_retired? || scheduled_end < 30.minutes.ago) if peer_id?

        !delivered_at? && (!airing || !airing.status.in?(Studio::Broadcasting::Airing::ACTIVE) || airing.ends_at < 30.minutes.ago)
      end

      scope :delivered, -> { where.not(delivered_at: nil) }
      attr_readonly :campaign_id, :station_site_id, :producer_id, :airing_id, :row_index,
        :station_cents, :producer_cents, :network_cents, :platform_cents

      def self.book!(airing:, rows:, producer:)
        campaign_ids = rows.filter_map { |row| row["ad_campaign_id"] }
        campaigns = Campaign.where(id: campaign_ids).order(:id).lock.index_by(&:id)
        station_id = airing.channel.site_id
        membership_networks = Membership.where(station_site_id: station_id, network_id: campaigns.values.map(&:network_id))
          .order(:id).lock.to_a.map(&:network_id)
        rows.each_with_index do |item, index|
          next unless item["ad_campaign_id"]
          campaign = campaigns[item.fetch("ad_campaign_id")]
          unless campaign&.open_for_booking? && campaign.creative_available? && campaign.seconds == item.fetch("seconds") &&
              ((campaign.network.site_id == station_id && !campaign.network.imported?) || membership_networks.include?(campaign.network_id))
            raise ArgumentError, "The ad campaign is unavailable for booking."
          end
          if campaign.producer_bps.positive? && !producer
            raise ArgumentError, "Choose a show project with a producer for this ad’s revenue share."
          end
          placement = create!(campaign: campaign, station_site_id: station_id, airing: airing, row_index: index,
            producer: campaign.producer_bps.positive? ? producer : nil, **campaign.split)
          if Exchange.connected?(placement.station_site)
            raise ArgumentError, "Publish this campaign to the ad exchange before booking." unless campaign.exchange_key?
            slot_start = airing.starts_at + rows.take(index).sum { |row| row.fetch("seconds") }
            placement.update!(exchange_key: SecureRandom.uuid, scheduled_start: slot_start, scheduled_end: slot_start + campaign.seconds,
              sync_after: Time.current)
          else
            Payment.reserve!(placement)
          end
        end
      end

      # Call inside the airing lock after the public feed accepted the segment.
      # A resumed or clock-seeked row only qualifies after a fresh start.
      def self.observe!(airing, row:, source:, offset:, boundary:, media_end:, final:)
        progress = airing.state["ad_progress"]
        if offset.abs <= 0.01
          progress = { "source" => source, "next_offset" => 0 }
        end
        unless progress && progress["source"] == source && (progress["next_offset"] - offset).abs <= 0.01
          airing.state = airing.state.except("ad_progress")
          return
        end

        if final
          if boundary >= media_end - 0.1
            matches = where(airing_id: airing.id, row_index: row, delivered_at: nil)
            matches.where.not(sync_after: nil).update_all(sync_after: Time.current)
            matches.update_all(delivered_at: Time.current, updated_at: Time.current)
          end
          airing.state = airing.state.except("ad_progress")
        else
          airing.state = airing.state.merge("ad_progress" => progress.merge("next_offset" => boundary))
        end
      end
    end
  end
end
