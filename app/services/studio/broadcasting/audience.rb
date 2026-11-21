# frozen_string_literal: true

module Studio
  module Broadcasting
    module Audience
      PURPOSE = "managed-channel"
      module_function

      def verifier = Rails.application.message_verifier("lightek-broadcast-audience")

      def path(channel:, outlet:, platform:)
        token = verifier.generate({
          "id" => SecureRandom.uuid, "channel_id" => channel.id, "outlet" => outlet.id, "platform" => platform
        }, purpose: PURPOSE, expires_in: 12.hours)
        "#{channel.managed_path}?#{URI.encode_www_form(view_session: token)}"
      end

      def identity(token, channel:, outlet:)
        return unless token.is_a?(String) && token.present? && token.bytesize <= 1_024
        claims = verifier.verified(token, purpose: PURPOSE)
        claims if claims.is_a?(Hash) && claims["channel_id"] == channel.id && claims["outlet"] == outlet.id &&
          Application::PLATFORMS.include?(claims["platform"])
      end

      def instrument_playlist(playlist, token)
        query = URI.encode_www_form(view_session: token)
        playlist.gsub(/^out-\d+\.ts$/) { |filename| "#{filename}?#{query}" }
      end

      def record(claims:, outlet:, channel:, path:)
        metadata = JSON.parse(File.read(path.sub_ext(".json"), 512))
        airtime = Time.iso8601(metadata.fetch("aired_at"))
        return unless airtime >= 2.minutes.ago && airtime <= Time.current
        return unless metadata.fetch("media_ms").is_a?(Integer) && metadata["media_ms"].between?(1, 10_000)
        sequence = Integer(path.basename.to_s.delete_prefix("out-").delete_suffix(".ts"))
        day = airtime.utc.to_date
        session_key = Digest::SHA256.hexdigest(claims.fetch("id"))
        context = { session_key: session_key, channel_id: channel.id, airing_id: metadata.fetch("airing_id"),
          ad_row: metadata.fetch("ad_row", -1), day: day }
        row = ViewSession.create_or_find_by!(context) do |entry|
          entry.assign_attributes(station_site_id: channel.site_id, outlet_site_id: outlet.id, platform: claims.fetch("platform"))
        end
        row.record(sequence, metadata.fetch("media_ms"))
      rescue Errno::ENOENT, JSON::ParserError, KeyError, ArgumentError
        nil
      rescue ActiveRecord::ActiveRecordError => error
        # Audience reporting never interrupts an otherwise accessible stream.
        Rails.logger.warn("[BroadcastAudience] channel=#{channel.id} error=#{error.class}")
      end
    end
  end
end
