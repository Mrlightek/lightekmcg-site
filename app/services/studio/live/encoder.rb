# frozen_string_literal: true
require "base64"
require "open3"
require "timeout"
require "fileutils"
module Studio
  module Live
    class Encoder
      class Failure < StandardError; end
      MAX_CHUNK = 1_048_576
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
      def initialize(output:, test:, on_event:, hls: false, relay_output: nil)
        @output, @test, @on_event, @hls = output.to_s, test, on_event, hls
        @relay_output = relay_output
        @mutex = Mutex.new
        @sequence = 0
        @started = @last_input = monotonic
      end
      def start!
        FileUtils.mkdir_p(File.dirname(@output), mode: 0o700) if @test || @hls
        args = [ENV.fetch("LIGHTEK_FFMPEG", "ffmpeg"), "-hide_banner", "-loglevel", "error", "-nostats", "-nostdin", "-y",
          "-protocol_whitelist", "pipe", "-fflags", "+genpts", "-probesize", "1000000", "-analyzeduration", "1000000", "-f", "webm", "-i", "pipe:0",
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
        # Never send FFmpeg stderr (which can include the stream key) to application logs.
        @input, @progress, @waiter = Open3.popen2(*args, err: File::NULL, pgroup: true)
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
          raise Failure, "The encoder has stopped." if @stopping || !@waiter&.alive?
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
      rescue ArgumentError, IOError, SystemCallError
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
      def read_progress
        reported = false
        @progress.each_line do |line|
          if line.start_with?("out_time_us=") && line.split("=", 2).last.to_i > 0 && !reported
            reported = true
            @on_event.call("sending", nil)
          end
        end
        status = @waiter.value
        @on_event.call(status.success? && @failure.nil? && reported ? "ended" : "failed", @failure || (status.success? && reported ? nil : "The encoder stopped before completing the stream. Check the destination and start a new session."))
      rescue IOError, SystemCallError
        @on_event.call("failed", "The encoder connection closed.")
      ensure
        @progress.close rescue nil
        @input.close rescue nil
      end
    end
  end
end
