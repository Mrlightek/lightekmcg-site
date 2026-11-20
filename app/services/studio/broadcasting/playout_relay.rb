# frozen_string_literal: true

module Studio
  module Broadcasting
    class PlayoutRelay
      def initialize(playlist)
        @playlist = playlist
      end

      def start!(airing)
        target = Studio::Live::Destination.output!(airing.operator, provider: airing.relay)
        @waiter = Process.detach(Process.spawn(PlayoutMedia.ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin",
          "-protocol_whitelist", "file,crypto", "-live_start_index", "-2", "-dts_delta_threshold", "0.3",
          "-i", @playlist.to_s, "-map", "0:v:0", "-map", "0:a:0",
          "-vf", "#{PlayoutMedia::SCALE},format=yuv420p", "-af", "aresample=async=1",
          *PlayoutMedia::CODECS, "-rw_timeout", "5000000", "-f", "flv", target,
          out: File::NULL, err: File::NULL, pgroup: true))
      end

      def running? = @waiter&.alive?

      def drain! = @waiter&.join(10)

      def stop!
        return unless running?
        Process.kill("TERM", -@waiter.pid)
        unless @waiter.join(2)
          Process.kill("KILL", -@waiter.pid)
          @waiter.join
        end
      rescue Errno::ESRCH
        nil
      end
    end
  end
end
