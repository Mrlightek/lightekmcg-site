# frozen_string_literal: true

require "net/http"
require "digest"

module Studio
  module Broadcasting
    module InstallationCarriage
      class Unavailable < StandardError; end
      class Rejected < Unavailable; end
      MAX_SEGMENT = 8.megabytes
      module_function

      def connected?(site)
        config = LightekReservations::Federation::Client.config(site)
        config && config.fetch("client_host", nil) == site.host
      end

      def sync!(entry, renew: false)
        channel = entry.channel
        return unless entry.remote_key? && connected?(channel.site)

        client = LightekReservations::Federation::Client.new(channel.site)
        schedule = channel.airings.where(status: %w[ready on_air], ends_at: Time.current..).order(:starts_at).limit(16).map do |airing|
          { title: airing.title, starts_at: airing.starts_at.iso8601, ends_at: airing.ends_at.iso8601, on_air: airing.status == "on_air" }
        end
        receipt = client.request("broadcast/channels/#{entry.remote_key}", method: :post, body: {
          name: channel.name, description: channel.description, published: NetworkCarriage.playable?(channel, user: nil),
          withdrawn: entry.status == "withdrawn", renew: renew, schedule: schedule
        })
        proof = receipt.fetch("relay_proof")
        unless proof.match?(/\A[0-9a-f]{64}\z/) && receipt.fetch("status").in?(%w[requested accepted withdrawn])
          raise Unavailable, "The network returned an invalid carriage receipt."
        end

        entry.with_lock do
          unless entry.status == "withdrawn" && receipt["status"] != "withdrawn"
            entry.update!(status: receipt["status"], ownership: receipt["ownership"], relay_digest: Digest::SHA256.hexdigest(proof))
          end
        end
      end

      def receive!(peer, key, payload)
        peer.with_lock do
          entry = HostedCarriage.find_or_initialize_by(key: key, peer: peer)
          status = entry.status
          status = "withdrawn" if payload["withdrawn"] == true
          status = "requested" if payload["renew"] == true && payload["withdrawn"] != true && status == "withdrawn"
          entry.update!(status: status, name: payload.fetch("name"), description: payload["description"],
            published: payload["published"] == true, schedule: parse_schedule(payload.fetch("schedule")))
          entry.touch
          { status: entry.status, ownership: entry.ownership, relay_proof: relay_proof(entry) }
        end
      end

      def parse_schedule(rows)
        raise ArgumentError, "Invalid remote program guide." unless rows.is_a?(Array) && rows.length <= 16

        rows.map do |row|
          start = Time.iso8601(row.fetch("starts_at"))
          finish = Time.iso8601(row.fetch("ends_at"))
          raise ArgumentError, "Invalid remote program window." unless finish > start && finish - start <= 2.hours
          { "title" => row.fetch("title").to_s.first(120), "starts_at" => start.iso8601,
            "ends_at" => finish.iso8601, "on_air" => row["on_air"] == true }
        end
      end

      def relay_proof(entry)
        secret = Rails.application.key_generator.generate_key("lightek-affiliate-relay", 32)
        OpenSSL::HMAC.hexdigest("SHA256", secret, "#{entry.peer.key}:#{entry.key}")
      end

      def authorize_edge!(entry, authorization)
        raise ActiveRecord::RecordNotFound unless entry.status == "accepted" && entry.relay_digest? &&
          authorization.to_s.match?(/\ABearer [0-9a-f]{64}\z/) &&
          ActiveSupport::SecurityUtils.secure_compare(entry.relay_digest, Digest::SHA256.hexdigest(authorization.delete_prefix("Bearer "))) &&
          NetworkCarriage.playable?(entry.channel, user: nil)
      end

      def relay!(entry, name, viewer:)
        raise Unavailable, "This installation is offline." unless entry.peer.active?

        host = entry.peer.site.host
        unless host.match?(/\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}\z/i)
          raise Unavailable, "The registered installation host is invalid."
        end
        path = "/gatekeeper/affiliate-source/#{entry.key}/#{name}"
        request = Net::HTTP::Get.new(path, "Authorization" => "Bearer #{relay_proof(entry)}")
        request["X-Lightek-Playback"] = viewer.fetch("id") if viewer
        request["X-Lightek-Platform"] = viewer.fetch("platform") if viewer
        type = metadata = nil
        bytes = +"".b
        limit = name.end_with?(".ts") ? MAX_SEGMENT : 64.kilobytes
        failover_probe = name == "index.m3u8" && entry.fallback_channel_id?
        Timeout.timeout(failover_probe ? 3 : 15) do
          Net::HTTP.start(host, 443, use_ssl: true, open_timeout: failover_probe ? 2 : 3, read_timeout: failover_probe ? 2 : 5) do |http|
            http.request(request) do |response|
              if name == "index.m3u8" && response.code.to_i.in?([401, 403, 404, 410])
                raise Rejected, "The source stopped authorizing carriage."
              end
              raise Unavailable, "The station feed is unavailable." unless response.is_a?(Net::HTTPOK)
              type = response["Content-Type"].to_s.split(";").first
              metadata = response["X-Lightek-Media"]
              response.read_body do |part|
                raise Unavailable, "The station feed exceeded its transfer limit." if bytes.bytesize + part.bytesize > limit
                bytes << part
              end
            end
          end
        end
        expected = name.end_with?(".ts") ? "video/mp2t" : (name.end_with?(".json") ? "application/json" : "application/vnd.apple.mpegurl")
        raise Unavailable, "The station feed returned an invalid media type." unless expected == type
        [bytes, type, metadata]
      rescue IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
        raise Unavailable, "The station feed is temporarily unavailable."
      end
    end
  end
end
