# frozen_string_literal: true

require "fileutils"

module Studio
  module Broadcasting
    class ChannelFeed
      WINDOW = 7
      def initialize(path)
        @path = path
        @playlist = path.join("index.m3u8")
        # A new publisher always starts at a higher sequence, even after a worker restart.
        previous = path.glob("out-*.ts").map { |entry| entry.basename.to_s[/\d+/].to_i }.max
        previous_playlist = @playlist.file? ? @playlist.read : ""
        last_sequence = previous_playlist[/#EXT-X-MEDIA-SEQUENCE:(\d+)/, 1].to_i + previous_playlist.scan(/^#EXTINF:/).size
        @sequence = [previous.to_i + 1, last_sequence].max
        @entries = []
        @discontinuities = previous_playlist[/#EXT-X-DISCONTINUITY-SEQUENCE:(\d+)/, 1].to_i +
          previous_playlist.scan(/^#EXT-X-DISCONTINUITY$/).size + (previous_playlist.empty? ? 0 : 1)
        @last_source = nil
      end

      def empty? = @entries.empty?
      def push(segment, source:, audience: nil, avail: nil)
        name = "out-#{@sequence}.ts"
        FileUtils.cp(segment.path, @path.join("#{name}.tmp"))
        File.rename(@path.join("#{name}.tmp"), @path.join(name))
        published_at = Time.current.utc.iso8601(3)
        if audience
          metadata = @path.join("out-#{@sequence}.json")
          temp_metadata = metadata.sub_ext(".json.tmp")
          temp_metadata.write(JSON.generate(audience.merge("aired_at" => published_at, "media_ms" => (segment.duration * 1000).round)))
          File.rename(temp_metadata, metadata)
        end
        discontinuity = @last_source && @last_source != source
        @last_source = source
        cues = ad_markers(avail, segment.duration)
        @entries << [@sequence, segment.duration, name, published_at, discontinuity, cues]
        @sequence += 1
        if @entries.size > WINDOW
          removed = @entries.shift
          @discontinuities += 1 if removed[4]
        end
        write!
        @path.glob("out-*.ts").each do |file|
          next unless file.basename.to_s[/\d+/].to_i < @entries.first.first && Time.now - file.mtime > 45
          FileUtils.rm_f([file, file.sub_ext(".json")])
        end
      end

      def finish!
        write!(finished: true) unless empty?
      end

      private

      def ad_markers(avail, duration)
        cues = []
        if @ad_avail && @ad_avail.fetch(:id) != avail&.fetch(:id)
          cues << "#EXT-X-CUE-IN"
          @ad_avail = nil
        end

        if @ad_avail
          cues << format("#EXT-X-CUE-OUT-CONT:%.3f/%d", @ad_avail.fetch(:elapsed), @ad_avail.fetch(:duration))
          @ad_avail[:elapsed] += duration
        elsif avail&.fetch(:starts_here)
          @ad_avail = avail.merge(elapsed: duration)
          cues << "#EXT-X-CUE-OUT:#{avail.fetch(:duration)}"
        end
        cues
      end

      def write!(finished: false)
        lines = ["#EXTM3U", "#EXT-X-VERSION:6", "#EXT-X-TARGETDURATION:#{target_duration}",
          "#EXT-X-INDEPENDENT-SEGMENTS", "#EXT-X-MEDIA-SEQUENCE:#{@entries.first.first}", "#EXT-X-DISCONTINUITY-SEQUENCE:#{@discontinuities}"]
        @entries.each do |_sequence, duration, name, published_at, discontinuity, cues|
          lines << "#EXT-X-DISCONTINUITY" if discontinuity
          lines << "#EXT-X-PROGRAM-DATE-TIME:#{published_at}"
          lines.concat(cues)
          lines << format("#EXTINF:%.6f,", duration) << name
        end
        if finished
          lines << "#EXT-X-CUE-IN" if @ad_avail
          lines << "#EXT-X-ENDLIST"
        end
        temporary = @path.join("index.m3u8.tmp")
        temporary.write(lines.join("\n") + "\n")
        File.rename(temporary, @playlist)
      end

      def target_duration = 2
    end
  end
end
