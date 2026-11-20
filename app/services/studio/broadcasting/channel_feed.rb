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
      def push(segment, source:)
        name = "out-#{@sequence}.ts"
        FileUtils.cp(segment.path, @path.join("#{name}.tmp"))
        File.rename(@path.join("#{name}.tmp"), @path.join(name))
        discontinuity = @last_source && @last_source != source
        @last_source = source
        @entries << [@sequence, segment.duration, name, discontinuity]
        @sequence += 1
        if @entries.size > WINDOW
          removed = @entries.shift
          @discontinuities += 1 if removed.last
        end
        write!
        @path.glob("out-*.ts").each do |file|
          file.delete if file.basename.to_s[/\d+/].to_i < @entries.first.first && Time.now - file.mtime > 45
        end
      end

      def finish!
        write!(finished: true) unless empty?
      end

      private

      def write!(finished: false)
        lines = ["#EXTM3U", "#EXT-X-VERSION:6", "#EXT-X-TARGETDURATION:#{target_duration}",
          "#EXT-X-INDEPENDENT-SEGMENTS", "#EXT-X-MEDIA-SEQUENCE:#{@entries.first.first}", "#EXT-X-DISCONTINUITY-SEQUENCE:#{@discontinuities}"]
        @entries.each do |_sequence, duration, name, discontinuity|
          lines << "#EXT-X-DISCONTINUITY" if discontinuity
          lines << format("#EXTINF:%.6f,", duration) << name
        end
        lines << "#EXT-X-ENDLIST" if finished
        temporary = @path.join("index.m3u8.tmp")
        temporary.write(lines.join("\n") + "\n")
        File.rename(temporary, @playlist)
      end

      def target_duration = 2
    end
  end
end
