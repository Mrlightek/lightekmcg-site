# frozen_string_literal: true

require "base64"
require "digest"

module Studio
  module Advertising
    module Exchange
      class Unavailable < StandardError; end
      MAX_CREATIVE = 6.megabytes
      KEY = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/
      TERMS = %w[name seconds rate_cents network_bps producer_bps platform_bps].freeze
      module_function

      def client(site)
        LightekReservations::Federation::Client.new(site)
      end

      def connected?(site)
        LightekReservations::Federation::Client.config(site).present?
      end

      def public_offers
        Campaign.offered.where(exchange_authority: true)
      end

      def serialize(campaign)
        {
          "key" => exchange_key!(campaign), "network_key" => exchange_key!(campaign.network),
          "network_name" => campaign.network.name
        }.merge(campaign.attributes.slice(*TERMS))
      end

      def exchange_key!(record)
        record.with_lock do
          record.update!(exchange_key: SecureRandom.uuid) unless record.exchange_key?
          record.exchange_key
        end
      end

      # The only media transferable on this path is the single ready ad proxy
      # that its owner chose to offer. Never accept a remote storage URL.
      def creative_payload(campaign)
        raise Unavailable, "The original ad video is unavailable." unless campaign.creative_available?

        blob = campaign.asset.proxy.blob
        raise Unavailable, "Use an ad video of 6 MB or less for network exchange." unless blob.byte_size.between?(1, MAX_CREATIVE)

        blob.open do |file|
          bytes = file.read(MAX_CREATIVE + 1)
          raise Unavailable, "The ad video exceeds the exchange limit." if bytes.bytesize > MAX_CREATIVE
          { "media" => Base64.strict_encode64(bytes), "sha256" => Digest::SHA256.hexdigest(bytes) }
        end
      end

      def publish!(site, campaign, open:)
        values = serialize(campaign).merge("open" => open, "merchant_key" => merchant_key(site))
        values.merge!(creative_payload(campaign)) if open
        client(site).request("ads/offers/#{values.fetch('key')}", method: :post, body: values)
        campaign.update!(open_for_booking: open)
      end

      def sales(site)
        client(site).request("ads/sales", method: :post, body: { "merchant_key" => merchant_key(site) })
      end

      def merchant_key(site)
        owner = site.tenant
        raise Unavailable, "Connect a business account before exchanging ads." unless owner.is_a?(::User)

        root = ENV["LIGHTEK_DEPLOYED_SITE_HOST"].presence
        root && DymondSite::Site.find_by(host: root)&.tenant_id != owner.id ? "user-#{owner.id}" : "owner"
      end

      def business!(peer, key)
        return [peer.merchant, peer.site] if key == "owner"

        connection = LightekCommerce::NetworkAccount.find_by!(peer: peer, source_subject: key)
        [connection.user, connection.site]
      end

      def catalog(site)
        client(site).request("ads/catalog").fetch("campaigns")
      end

      def import!(site, key)
        identifier!(key)
        attributes = client(site).request("ads/offers/#{key}")
        save_copy!(site: site, actor: site.tenant, attributes: attributes, imported: true)
      end

      def receive_offer!(peer, key, attributes)
        identifier!(key)
        peer.with_lock do
          merchant, site = business!(peer, attributes.fetch("merchant_key"))
          owned = Campaign.joins(:network).where(exchange_key: key, studio_ad_networks: { peer_id: peer.id, site_id: site.id })
          unless attributes.fetch("open") == true
            owned.find_by(exchange_key: key)&.update!(open_for_booking: false)
            return { "key" => key, "open" => false }
          end

          if Campaign.where(exchange_authority: true).exists?(exchange_key: key) && !owned.exists?
            raise Unavailable, "This ad offer belongs to another installation."
          end

          campaign = save_copy!(site: site, actor: merchant, attributes: attributes.merge("key" => key),
            imported: false, peer: peer)
          { "key" => campaign.exchange_key, "open" => true }
        end
      end

      def save_copy!(site:, actor:, attributes:, imported:, peer: nil)
        raise Unavailable, "Connect a business account before exchanging ads." unless actor.is_a?(::User)
        network_key = identifier!(attributes.fetch("network_key"))
        offer_key = identifier!(attributes.fetch("key"))
        network = Network.find_or_create_by!(site: site, exchange_key: network_key) do |record|
          record.assign_attributes(name: attributes.fetch("network_name"), imported: imported, peer: peer)
        end
        unless network.imported? == imported && network.peer_id == peer&.id
          raise Unavailable, "Ad network ownership differs from the exchange receipt."
        end

        network.with_lock do
          existing = network.campaigns.find_by(exchange_key: offer_key)
          if existing
            unless existing.attributes.slice(*TERMS) == attributes.slice(*TERMS) &&
                existing.creative_sha256 == attributes.fetch("sha256") && existing.creative_available?
              raise Unavailable, "The exchanged ad differs from the existing offer."
            end

            existing.update!(open_for_booking: true)
            return existing
          end

          bytes = Base64.strict_decode64(attributes.fetch("media"))
          unless bytes.bytesize.between?(1, MAX_CREATIVE) && Digest::SHA256.hexdigest(bytes) == attributes.fetch("sha256")
            raise Unavailable, "Ad video failed its integrity check."
          end

          seconds, audio = inspect_media!(bytes)
          asset = StudioAsset.create!(site: site, owner: actor, kind: "video", status: "ready", name: "Network ad",
            request_key: SecureRandom.uuid, metadata: { "duration" => seconds, "has_audio" => audio, "network_ad_exchange" => "reserved" })
          asset.proxy.attach(io: StringIO.new(bytes), filename: "network-ad.mp4", content_type: "video/mp4", identify: false)
          network.campaigns.create!(attributes.slice(*TERMS).merge(asset: asset, blob_id: asset.proxy.blob.id,
            exchange_key: offer_key, exchange_authority: !imported, creative_sha256: attributes.fetch("sha256"), open_for_booking: true))
        end
      end

      def inspect_media!(bytes)
        Studio::MediaProcess.temporary_directory("ad-exchange-") do |directory|
          path = File.join(directory, "creative.mp4")
          File.binwrite(path, bytes)
          output = Studio::MediaProcess.run!([ENV.fetch("LIGHTEK_FFPROBE", "ffprobe"), "-v", "error",
            "-protocol_whitelist", "file", "-format_whitelist", "mov,mp4,m4a,3gp,3g2,mj2", "-show_entries", "format=duration:stream=codec_type",
            "-of", "json", path], timeout: 15)
          media = JSON.parse(output)
          types = media.fetch("streams").pluck("codec_type")
          duration = Float(media.fetch("format").fetch("duration"))
          unless types.include?("video") && duration.finite? && duration.between?(2, 120)
            raise Unavailable, "Use an MP4 ad between 2 and 120 seconds."
          end
          [duration, types.include?("audio")]
        end
      rescue JSON::ParserError, KeyError, ArgumentError, RuntimeError, Timeout::Error
        raise Unavailable, "The exchanged ad video could not be read."
      end

      def sync_placement!(placement)
        airing = placement.airing
        site = placement.station_site
        raise Unavailable, "The campaign is missing its exchange reference." unless placement.campaign.exchange_key?

        data = client(site).request("ads/placements/#{placement.exchange_key}", method: :post, body: {
          "campaign_key" => placement.campaign.exchange_key, "starts_at" => placement.scheduled_start.iso8601,
          "ends_at" => placement.scheduled_end.iso8601, "producer_key" => producer_key(placement),
          "merchant_key" => merchant_key(site),
          "published" => airing&.channel&.status == "published",
          "delivered_at" => placement.delivered_at&.iso8601, "retired" => placement.finished_without_delivery?
        })
        state = data.fetch("state")
        raise Unavailable, "The placement returned an invalid payment state." unless state.in?(%w[unfunded authorized captured held void])
        terminal = state.in?(%w[captured held void])
        placement.update!(remote_state: state, remote_authorized_until: data["authorized_until"],
          sync_after: terminal ? nil : 1.minute.from_now)
      end

      def producer_key(placement)
        return unless placement.producer_id

        placement.producer_id == placement.station_site.tenant_id ? "owner" : "user-#{placement.producer_id}"
      end

      def receive_placement!(peer, key, attrs)
        identifier!(key)
        peer.with_lock do
          placement = Placement.where(peer: peer).find_by(exchange_key: key)
          merchant, site = business!(peer, attrs.fetch("merchant_key"))
          placement ||= reserve_remote!(peer, key, attrs, merchant: merchant, site: site)
          raise Unavailable, "The delivery belongs to another station." unless placement.station_site_id == site.id
          placement.with_lock do
            if attrs["delivered_at"].present? && !placement.delivered_at?
              delivered_at = Time.iso8601(attrs["delivered_at"])
              unless !placement.remote_retired? && placement.remote_state == "published" && placement.payment.ready_at?(placement.scheduled_end) &&
                  delivered_at.between?(placement.scheduled_end - 2.seconds, placement.scheduled_end + 10.minutes) && delivered_at <= 1.minute.from_now
                raise Unavailable, "The delivery does not match the authorized airtime."
              end
              placement.update!(delivered_at: delivered_at)
              placement.payment.update!(reconcile_after: Time.current)
            elsif attrs["retired"] == true && !placement.delivered_at?
              placement.update!(remote_retired: true)
              placement.payment.with_lock do
                if placement.payment.checkout_requested_at?
                  placement.payment.update!(reconcile_after: Time.current)
                else
                  placement.payment.update!(state: "void", reconcile_after: nil)
                end
              end
            end
            published = attrs["published"] == true
            placement.update!(remote_state: published ? "published" : "private") unless placement.delivered_at?
            payment = placement.payment.reload
            { "state" => payment.state, "authorized_until" => payment.authorized_until&.iso8601 }
          end
        end
      end

      def reserve_remote!(peer, key, attrs, merchant:, site:)
        starts_at = Time.iso8601(attrs.fetch("starts_at"))
        ends_at = Time.iso8601(attrs.fetch("ends_at"))
        unless starts_at.between?(2.minutes.ago, 90.days.from_now) && ends_at > starts_at && ends_at - starts_at <= 2.hours
          raise Unavailable, "Invalid broadcast reservation window."
        end

        campaign = public_offers.find_by!(exchange_key: identifier!(attrs.fetch("campaign_key")))
        raise Unavailable, "The ad video is unavailable." unless campaign.creative_available?
        raise Unavailable, "The reserved ad length does not match the campaign." unless (ends_at - starts_at) == campaign.seconds

        producer = if campaign.producer_bps.positive?
          if attrs["producer_key"] == "owner"
            merchant
          else
            LightekCommerce::NetworkAccount.find_by!(peer: peer, source_subject: attrs.fetch("producer_key")).user
          end
        end
        placement = Placement.create!(peer: peer, exchange_key: key, campaign: campaign, station_site: site,
          row_index: 0, producer: producer, scheduled_start: starts_at, scheduled_end: ends_at, **campaign.split)
        Payment.reserve!(placement)
        placement
      end

      def identifier!(value)
        raise Unavailable, "Invalid ad exchange reference." unless KEY.match?(value.to_s)
        value.to_s
      end
    end
  end
end
