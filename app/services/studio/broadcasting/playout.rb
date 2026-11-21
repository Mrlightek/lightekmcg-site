# frozen_string_literal: true

module Studio
  module Broadcasting
    class Playout
      LEAD = 28.seconds

      def initialize(channel)
        @channel = channel
        @path = PlayoutMedia.channel_path(channel.id)
        @relay = PlayoutRelay.new(@path.join("index.m3u8"))
        @prepared_rows = {}
      end

      def run
        FileUtils.mkdir_p(@path, mode: 0o700)
        File.open(@path.join("publisher.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
          return unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          run_feed
        end
      end

      private

      def run_feed
        @feed = ChannelFeed.new(@path)
        @standby = PlayoutMedia.standby(@channel.id)
        deadline = monotonic
        loop do
          unless @channel.reload.managed_playout? && @channel.status != "off_air"
            stop_active_channel
            break
          end
          airing = airing_at(Time.current)
          break unless airing
          seconds = airing.starts_at.future? ? standby : publish(airing)
          next unless seconds
          deadline = [deadline + seconds, monotonic].max
          sleep(deadline - monotonic) if deadline > monotonic
        end
      rescue StandardError => error
        @active&.with_lock do
          @active.update!(status: "failed", error_message: "Channel playout stopped. Check the channel worker and media.") if %w[ready on_air].include?(@active.status)
        end
        Rails.logger.error("[StudioPlayout] channel=#{@channel.id} error=#{error.class}")
      ensure
        @feed&.finish!
        @relay.drain!
        @relay.stop!
      end

      def stop_active_channel
        airing = @channel.airings.find_by(status: "on_air")
        airing&.with_lock do
          if airing.status == "on_air"
            airing.record_event!("ended", "reason" => "channel_off_air")
            airing.update!(status: "completed", events: airing.events)
          end
        end
      end

      def airing_at(now)
        current = @channel.airings.find_by(status: "on_air")
        upcoming = @channel.airings.where(status: "ready", starts_at: ..(now + LEAD)).order(:starts_at).first
        if current && upcoming && upcoming.starts_at <= now
          current.with_lock do
            current.record_event!("ended", "reason" => "next_airtime")
            current.update!(status: "completed", events: current.events)
          end
          current = nil
        end
        current || upcoming
      end

      def standby
        @feed.push(@standby, source: Object.new)
        @standby.duration
      end

      def publish(airing)
        airing.with_lock do
          return unless %w[ready on_air].include?(airing.status)
          @active = airing
          if airing.status == "ready"
            return expire(airing) if airing.ends_at <= Time.current
            Studio::Broadcasting::Access.authorize!(airing.operator, @channel.site)
            ::Gatekeeper::StudioLivePolicy.authorize!(user: airing.operator)
            airing.status = "on_air"
            late_by = Time.current - airing.starts_at
            airing.state = airing.state.merge("position" => late_by > 3 ? late_by : 0)
            airing.record_event!("started")
          end
          @prepared_rows.clear if @prepared_for != airing.id
          @prepared_for = airing.id
          seconds = airing.state["input"] ? publish_input(airing) : publish_rundown(airing)
          manage_relay(airing) if seconds
          airing.save!
          seconds
        end
      end

      def expire(airing)
        airing.update!(status: "failed", error_message: "The playout worker missed this airtime.")
        nil
      end

      def rundown_media(airing, index, item)
        @prepared_rows[index] ||= begin
          directory = PlayoutMedia.airing_path(airing.id)
          ad_media = PlayoutMedia.segments(directory.join("ad-#{index}")) if item["ad_campaign_id"]
          if ad_media && ad_media.sum(&:duration) >= item.fetch("seconds") - 0.1
            [ad_media, true]
          else
            [PlayoutMedia.segments(directory.join(index.to_s)), false]
          end
        end
      end

      def publish_rundown(airing)
        row = airing.row_at(airing.position)
        unless row
          airing.record_event!("returned", "mode" => airing.state["return"]) if airing.state["return"]
          airing.record_event!("ended")
          airing.status = "completed"
          return nil
        end
        index, offset, finishing = row
        item = airing.rundown.fetch(index)
        media, ad = rundown_media(airing, index, item)
        boundary = 0
        segment = media.find { |part| (boundary += part.duration) > offset + 0.01 }
        # Sub-frame differences in indexed media should not repeat or skip a row.
        segment ||= media.last if offset < airing.rundown.fetch(index).fetch("seconds")
        raise "Scheduled media is missing" unless segment
        source = "airing-#{airing.id}-row-#{index}"
        # Seeking within a row resets its media timestamps too.
        generation = airing.state.fetch("generation", 0)
        @feed.push(segment, source: [source, generation])
        if ad && @channel.status == "published"
          Advertising::Placement.observe!(airing, row: index, source: [source, generation],
            offset: boundary - segment.duration, boundary: boundary, media_end: item.fetch("seconds"), final: segment.equal?(media.last))
        else
          airing.state = airing.state.except("ad_progress")
        end
        if airing.state["return"]
          airing.record_event!("returned", "mode" => airing.state["return"])
          airing.state = airing.state.except("return")
        end
        if airing.state["source"] != source
          airing.record_event!("ad_backup", "row" => index + 1) if item["ad_campaign_id"] && !ad
          airing.record_event!("row_aired", "row" => index + 1, "label" => item.fetch("label"), "kind" => item.fetch("kind"), "sponsor" => item.fetch("sponsor"), "offset" => (boundary - segment.duration).round(2))
        end
        position = finishing - airing.rundown.fetch(index).fetch("seconds") + boundary
        airing.state = airing.state.merge("source" => source, "position" => [position, finishing].min)
        segment.duration
      end

      def publish_input(airing)
        operation_id = airing.state.fetch("input")
        operation = StudioLiveOperation.find_by(id: operation_id, status: "live")
        unless operation && operation.studio_project.site_id == @channel.site_id && operation.metadata["destination"] == "channel_input" && operation.updated_at > 25.seconds.ago
          airing.state = airing.state.except("input", "input_segment").merge("return" => "input_ended", "generation" => airing.state.fetch("generation", 0) + 1)
          return publish_rundown(airing)
        end
        source = "input-#{operation_id}"
        segments = PlayoutMedia.segments(Studio::Live::Encoder.hls_directory(operation_id))
        last = airing.state["input_segment"]
        segment = last ? segments.find { |part| segment_number(part) > last } : segments.last
        unless segment
          @waiting_for_input ||= monotonic
          return 0.15 if monotonic - @waiting_for_input < 1
          @waiting_for_input = nil
          return standby
        end
        @waiting_for_input = nil

        generation = airing.state.fetch("generation", 0)
        if last && segment_number(segment) != last + 1
          generation += 1
        end
        @feed.push(segment, source: [source, generation])
        airing.record_event!("cut_in", "input" => operation_id) if airing.state["source"] != source
        airing.state = airing.state.merge("source" => source, "input_segment" => segment_number(segment), "generation" => generation)
        segment.duration
      end

      def segment_number(segment) = segment.key[/\d+/].to_i

      def manage_relay(airing)
        return if @feed.empty?
        identity = [airing.operator_id, airing.relay]
        if @channel.status != "published"
          @relay.stop!
          @relay_identity = nil
          return
        end
        if identity != @relay_identity
          @relay.stop!
          @relay_identity = identity
          @relay_failed = false
          @relay.start!(airing) if airing.relay
        elsif airing.relay && !@relay.running? && !@relay_failed
          record_relay_failure(airing)
        end
      rescue Studio::Live::Destination::Unavailable, SystemCallError
        record_relay_failure(airing)
      end

      def record_relay_failure(airing)
        @relay_failed = true
        airing.record_event!("relay_failed", "provider" => airing.relay)
        airing.error_message = "The social relay stopped or could not connect. Channel playback continues."
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
