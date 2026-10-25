require "test_helper"
require "tmpdir"
require "json"
class StudioLiveEncoderTest < ActiveSupport::TestCase
  setup do
    skip "Server FFmpeg is not installed" unless Studio::Live::Encoder.available?
    @directory = Dir.mktmpdir("lightek-live-test-")
    @events = Queue.new
  end
  teardown do
    @encoder&.stop!
    FileUtils.remove_entry(@directory) if @directory && File.directory?(@directory)
  end
  def encoder
    @encoder ||= Studio::Live::Encoder.new(output: File.join(@directory, "test.mp4"), test: true, on_event: ->(event, error) { @events << [event, error] }).start!
  end
  def terminal_event
    Timeout.timeout(10) do
      loop do
        event = @events.pop
        return event if %w[ended failed].include?(event.first)
      end
    end
  end
  test "real encoder creates H264 AAC MP4 from ordered WebM chunks" do
    input = File.join(@directory, "capture.webm")
    _out, status = Open3.capture2(ENV.fetch("LIGHTEK_FFMPEG", "ffmpeg"), "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "2", "-c:v", "libvpx", "-deadline", "realtime", "-b:v", "250k", "-c:a", "libopus", input, err: File::NULL)
    assert status.success?, "FFmpeg fixture generation failed"
    File.binread(input).bytes.each_slice(24000).with_index do |bytes, sequence|
      assert_equal sequence, encoder.append!(encoded: Base64.strict_encode64(bytes.pack("C*")), sequence: sequence)
    end
    encoder.stop!
    assert_equal ["ended", nil], terminal_event
    output, result = Open3.capture2("ffprobe", "-v", "error", "-show_streams", "-of", "json", File.join(@directory, "test.mp4"), err: File::NULL)
    assert result.success?
    codecs = JSON.parse(output).fetch("streams").map { |stream| stream["codec_name"] }
    assert_includes codecs, "h264"
    assert_includes codecs, "aac"
  end
  test "invalid oversized and reordered capture chunks are rejected" do
    assert_raises(Studio::Live::Encoder::Failure) { encoder.append!(encoded: "%%%", sequence: 0) }
    assert_raises(Studio::Live::Encoder::Failure) { encoder.append!(encoded: "a" * 1_500_000, sequence: 0) }
    assert_raises(Studio::Live::Encoder::Failure) { encoder.append!(encoded: Base64.strict_encode64("fixture"), sequence: 1) }
  end
  test "missing input watchdog terminates the process" do
    encoder.instance_variable_set(:@last_input, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 20)
    event, error = terminal_event
    assert_equal "failed", event
    assert_equal "Capture stopped sending data.", error
    refute encoder.instance_variable_get(:@waiter).alive?
  end
end
