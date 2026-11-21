# frozen_string_literal: true

module Studio
  module Broadcasting
    class AffiliateFailover
      PLAYLIST_TYPE = "application/vnd.apple.mpegurl"
      BACKUP_SEGMENT = /\Afallback-(\d+)-(out-\d+\.ts)\z/

      def initialize(entry, outlet:, viewer:)
        @entry, @outlet, @viewer = entry, outlet, viewer
      end

      def fetch(name)
        if name == "index.m3u8"
          return playlist
        elsif name == "measurement.json" && @entry.relay_cursor["source"].to_s.start_with?("fallback-")
          return [JSON.generate(timeline: []), "application/json", nil]
        elsif (match = BACKUP_SEGMENT.match(name))
          channel = fallback_channel
          raise ActiveRecord::RecordNotFound unless match[1].to_i == channel.id

          path = PlayoutMedia.channel_path(channel.id).join(match[2])
          raise ActiveRecord::RecordNotFound unless path.file? && path.size.between?(1, InstallationCarriage::MAX_SEGMENT)

          return [path.binread, "video/mp2t", nil]
        end

        InstallationCarriage.relay!(@entry, name, viewer: @viewer)
      end

      private

      def playlist
        source = "station"
        begin
          body = InstallationCarriage.relay!(@entry, "index.m3u8", viewer: @viewer).first
          validate_live!(body)
        rescue InstallationCarriage::Rejected
          raise
        rescue InstallationCarriage::Unavailable
          channel = fallback_channel
          body = PlayoutMedia.channel_path(channel.id).join("index.m3u8").read(64.kilobytes + 1)
          validate_live!(body)
          source = "fallback-#{channel.id}"
        end

        [continue_playlist(body, source), PLAYLIST_TYPE, nil]
      rescue Errno::ENOENT
        raise InstallationCarriage::Unavailable, "The backup channel is off air."
      end

      def fallback_channel
        channel = @entry.fallback_channel
        unless @entry.peer.active? && channel&.site_id == @outlet.id && NetworkCarriage.playable?(channel, user: nil)
          raise InstallationCarriage::Unavailable, "The backup channel is unavailable."
        end

        channel
      end

      def validate_live!(body)
        timestamps = body.to_s.scan(/^#EXT-X-PROGRAM-DATE-TIME:([^\r\n]+)/).flatten
        latest = Time.iso8601(timestamps.last.to_s) unless timestamps.empty?
        unless body && body.bytesize <= 64.kilobytes && body.start_with?("#EXTM3U\n") && !body.include?("#EXT-X-ENDLIST") &&
            latest && latest.between?(12.seconds.ago, 5.seconds.from_now) && body.match?(/^#EXT-X-MEDIA-SEQUENCE:\d+$/) &&
            body.match?(/^#EXT-X-DISCONTINUITY-SEQUENCE:\d+$/) &&
            body.lines.all? { |line| line.start_with?("#") ? !line.match?(/\bURI=/i) : line.match?(/\Aout-\d+\.ts\n?\z/) } &&
            body.scan(/^out-\d+\.ts$/).size.between?(1, ChannelFeed::WINDOW)
          raise InstallationCarriage::Unavailable, "The feed stopped publishing fresh segments."
        end
      rescue ArgumentError
        raise InstallationCarriage::Unavailable, "The feed returned an invalid timestamp."
      end

      def continue_playlist(body, source)
        sequence = body[/^#EXT-X-MEDIA-SEQUENCE:(\d+)$/, 1].to_i
        discontinuity = body[/^#EXT-X-DISCONTINUITY-SEQUENCE:(\d+)$/, 1].to_i
        count = body.scan(/^out-\d+\.ts$/).size
        cuts = body.scan(/^#EXT-X-DISCONTINUITY$/).size
        cursor = @entry.with_lock do
          raise ActiveRecord::RecordNotFound unless @entry.status == "accepted" && @entry.published? && @entry.peer.active?
          raise InstallationCarriage::Unavailable, "The backup channel changed." if source.start_with?("fallback-") && source != "fallback-#{@entry.fallback_channel_id}"

          previous = @entry.relay_cursor
          reset = previous["source"] != source || sequence + count - 1 < previous.fetch("upstream_first", 0) ||
            discontinuity < previous.fetch("upstream_discontinuity", 0)
          offset = reset ? previous.fetch("last", sequence - 1) + 1 - sequence : previous.fetch("offset")
          cut_offset = reset ? previous.fetch("last_cut", discontinuity - 1) + 1 - discontinuity : previous.fetch("cut_offset")
          updated = { "source" => source, "offset" => offset, "cut_offset" => cut_offset,
            "last" => [sequence + offset + count - 1, previous.fetch("last", 0)].max,
            "last_cut" => [discontinuity + cut_offset + cuts, previous.fetch("last_cut", 0)].max,
            "upstream_first" => sequence, "upstream_discontinuity" => discontinuity }
          @entry.update_columns(relay_cursor: updated) unless updated == previous
          updated
        end
        body = body.sub(/^#EXT-X-MEDIA-SEQUENCE:\d+$/, "#EXT-X-MEDIA-SEQUENCE:#{sequence + cursor.fetch('offset')}")
          .sub(/^#EXT-X-DISCONTINUITY-SEQUENCE:\d+$/, "#EXT-X-DISCONTINUITY-SEQUENCE:#{discontinuity + cursor.fetch('cut_offset')}")
        source == "station" ? body : body.gsub(/^out-\d+\.ts$/) { |segment| "#{source}-#{segment}" }
      end
    end
  end
end
