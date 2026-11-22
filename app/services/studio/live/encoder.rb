# frozen_string_literal: true
require "base64"
require "open3"
require "timeout"
require "fileutils"
module Studio
  module Live
    class Encoder
      class Failure < StandardError; end
      class InputClosed < Failure; end

      # Only fixed messages leave this process. FFmpeg may include the stream
      # key or other private destination details in its diagnostics.
      DESTINATION_FAILURES = {
        /(?:NetStream\.Publish\.(?:BadName|Denied|Rejected)|publish(?:ing)?[^\n]*(?:denied|rejected)|invalid stream key)/i =>
          "The streaming destination rejected publishing. Verify the stream key and check for another active broadcast.",
        /(?:connection refused|network is unreachable|no route to host|failed to resolve hostname)/i =>
          "The streaming destination refused the connection. Check the saved destination and try again.",
        /(?:certificate verify failed|TLS handshake|unexpected TLS packet)/i =>
          "The streaming destination could not establish a secure connection.",
        /(?:connection reset by peer|connection timed out|I\/O timeout|broken pipe)/i =>
          "The connection to the streaming destination dropped or timed out."
      }.freeze
      LOCAL_FAILURES = {
        /(?:no space left on device|disk quota exceeded)/i => "The broadcast server ran out of space while writing video.",
        /(?:EBML header parsing failed|moov atom not found|invalid data found when processing input|matches no streams)/i =>
          "The encoder could not read the browser capture. Reopen Live Studio and try a private recording."
      }.freeze
      MAX_CHUNK = 1_048_576
      CAPTURE_FORMATS = { "webm" => "webm", "mp4" => "mov" }.freeze

      def self.capture_format(container)
        CAPTURE_FORMATS.fetch(container) { raise Failure, "This capture format is unsupported. Reopen Live Studio and try again." }
      end
      def self.available?
        _out, status = Open3.capture2(ENV.fetch("LIGHTEK_FFMPEG", "ffmpeg"), "-version", err: File::NULL)
        status.success?
      rescue SystemCallError
        false
      end
      def self.recording_path(id)
        raise ArgumentError, "Invalid session" unless id.to_s.match?(/\A\d+\z/)
        Rails.root.join("tmp", "studio_live", "#{id}.mp4")
      end
      def self.hls_directory(id)
        raise ArgumentError,"Invalid live session" unless id.to_s.match?(/\A\d+\z/)
        Rails.root.join("tmp","studio_live_hls",id.to_s)
      end
      def self.hls_path(id) = hls_directory(id).join("index.m3u8")
      def initialize(output:, test:, on_event:, hls: false, relay_output: nil, input_format: "webm")
        @output, @test, @on_event, @hls = output.to_s, test, on_event, hls
        @relay_output = relay_output
        raise Failure, "Unsupported encoder input." unless CAPTURE_FORMATS.value?(input_format)
        @input_format = input_format
        @network_output = @relay_output || (!@test && !@hls)
        @mutex = Mutex.new
        @sequence = 0
        @started = @last_input = monotonic
      end
      def start!
        FileUtils.mkdir_p(File.dirname(@output), mode: 0o700) if @test || @hls
        args = [ENV.fetch("LIGHTEK_FFMPEG", "ffmpeg"), "-hide_banner", "-loglevel", "error", "-nostats", "-nostdin", "-y",
          "-protocol_whitelist", "pipe", "-fflags", "+genpts", "-probesize", "1000000", "-analyzeduration", "1000000", "-f", @input_format, "-i", "pipe:0",
          "-map", "0:v:0", "-map", "0:a:0", "-vf", "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=yuv420p",
          "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency", "-threads", "2", "-r", "24", "-g", "48", "-b:v", "1800k", "-maxrate", "1800k", "-bufsize", "3600k",
          "-c:a", "aac", "-b:a", "96k", "-ar", "44100", "-progress", "pipe:1"]
        args += if @hls
          ["-f","hls","-hls_time","2","-hls_list_size","8","-hls_flags","delete_segments+independent_segments","-hls_segment_filename",File.join(File.dirname(@output),"segment-%06d.ts"),@output]
        elsif @test
          ["-movflags", "+faststart", "-f", "mp4", @output]
        else
          ["-rw_timeout", "5000000", "-f", "flv", @output]
        end
        if @relay_output
          raise Failure, "Simulcast requires a Lightek HLS output." unless @hls
          # Separate muxers in one supervised process: both destinations must
          # remain healthy for the session to report successful delivery.
          args += ["-map", "0:v:0", "-map", "0:a:0", "-vf", "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=yuv420p",
            "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency", "-threads", "2", "-r", "24", "-g", "48", "-b:v", "1800k",
            "-c:a", "aac", "-b:a", "96k", "-ar", "44100", "-rw_timeout", "5000000", "-f", "flv", @relay_output.to_s]
        end
        @input, @progress, @stderr, @waiter = Open3.popen3(*args, pgroup: true)
        @diagnostics = Thread.new { read_diagnostics }
        @reader = Thread.new { read_progress }
        @watchdog = Thread.new do
          loop do
            sleep 1
            break unless @waiter.alive?
            if monotonic - @last_input > 15
              stop!(failure: "Capture stopped sending data.")
              break
            elsif monotonic - @started > (@test ? 120 : 7200)
              stop!
              break
            end
          end
        end
        self
      rescue SystemCallError
        raise Failure, "The server encoder could not start. Check FFmpeg installation."
      end
      def append!(encoded:, sequence:)
        raise Failure, "Capture chunk is too large." unless encoded.is_a?(String) && encoded.bytesize <= ((MAX_CHUNK + 2) / 3) * 4
        bytes = Base64.strict_decode64(encoded)
        raise Failure, "Capture chunk is empty or too large." unless bytes.bytesize.between?(1, MAX_CHUNK)
        @mutex.synchronize do
          raise Failure, "Capture sequence changed. Start a new session." unless sequence == @sequence
          raise InputClosed, "The encoder input is closed." if @stopping || !@waiter&.alive?
          deadline = monotonic + 5
          offset = 0
          while offset < bytes.bytesize
            result = @input.write_nonblock(bytes.byteslice(offset..), exception: false)
            if result == :wait_writable
              raise Failure, "The encoder is not keeping up. Restart at a lower capture load." if monotonic >= deadline
              IO.select(nil, [@input], nil, 0.1)
            else
              offset += result
            end
          end
          @last_input = monotonic
          @sequence += 1
        end
        sequence
      rescue Errno::EPIPE, IOError
        raise InputClosed, "The encoder input is closed."
      rescue ArgumentError, SystemCallError
        raise Failure, "Capture data could not be sent to the encoder."
      end
      def stop!(failure: nil)
        @mutex.synchronize do
          return if @stopping
          @stopping = true
          @failure = failure
          @input.close unless @input.closed?
        end
        unless @waiter.join(6)
          Process.kill("TERM", -@waiter.pid) rescue nil
          unless @waiter.join(2)
            Process.kill("KILL", -@waiter.pid) rescue nil
            @waiter.join(2)
          end
        end
      end
      private
      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      def read_diagnostics
        failure = nil
        @stderr.each_line(4096) do |line|
          match = LOCAL_FAILURES.find { |pattern, _message| pattern.match?(line) }
          match ||= DESTINATION_FAILURES.find { |pattern, _message| pattern.match?(line) } if @network_output
          failure ||= match&.last
        end
        failure
      rescue IOError, SystemCallError
        failure
      ensure
        @stderr.close
      end

      def read_progress
        reported = false
        @progress.each_line do |line|
          if line.start_with?("out_time_us=") && line.split("=", 2).last.to_i > 0 && !reported
            reported = true
            @on_event.call("sending", nil)
          end
        end
        status = @waiter.value
        success = status.success? && @failure.nil? && reported
        failure = @failure || @diagnostics.value
        fallback = "The encoder stopped before completing the stream. Check the destination and start a new session."
        @on_event.call(success ? "ended" : "failed", success ? nil : failure || fallback)
      rescue IOError, SystemCallError
        @on_event.call("failed", "The encoder connection closed.")
      ensure
        @progress.close rescue nil
        @input.close rescue nil
      end
    end
  end
end
