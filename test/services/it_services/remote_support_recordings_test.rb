require "test_helper"
require "tempfile"

class ItServicesRemoteSupportRecordingsTest < ActiveSupport::TestCase
  Recordings = ItServices::RemoteSupportRecordings
  ScreenShare = ItServices::RemoteScreenShare
  Denied = Gatekeeper::ItRemoteSupportPolicy::Denied

  setup do
    skip "Batch B IT Service Requests migrations are required" unless ItRemoteSupportSession.available?
    @customer = create_user("client")
    @technician = create_user("contractor")
    @customer_login = Session.create!(user: @customer)
    @technician_login = Session.create!(user: @technician, mfa_verified_at: Time.current)
    LightekIdentity::Factor.create!(user: @technician, enabled_at: Time.current, secret_box: {})
    work = ItServiceRequest.create!(user: @customer, technician: @technician, service_code: "computer_repair",
      status: "in_progress", delivery_mode: "remote", description: "Inspect a computer issue with the customer.")
    @room = ScreenShare.request!(work, @technician_login)
    ScreenShare.approve!(@room, @customer_login)
  end

  test "both parties approve independently and only the customer may start after video is displayed" do
    Recordings.consent!(@room, @customer_login)
    assert_raises(ScreenShare::Conflict) { Recordings.start!(@room, @customer_login) }
    Recordings.consent!(@room, @technician_login)
    assert_raises(Denied) { Recordings.start!(@room, @technician_login) }
    assert_raises(ScreenShare::Conflict) { Recordings.start!(@room, @customer_login) }
    @room.update!(display_reported_at: Time.current)
    Recordings.start!(@room, @customer_login)
    assert_raises(ScreenShare::Conflict) { Recordings.start!(@room, @customer_login) }
    assert Recordings.status(@room).fetch(:started)
  end

  test "validates and encrypts a real WebM upload and permits playback by the assigned participants until revoked" do
    start_recording
    upload_video do |file, bytes|
      record = Recordings.store!(@room, @customer_login, file)
      refute_equal Base64.strict_encode64(bytes), record.payload
      assert_raises(ScreenShare::Conflict) { Recordings.store!(@room, @customer_login, file) }

      ScreenShare.end!(@room, @customer_login)
      assert_equal bytes, Recordings.playback!(@room, @technician_login)
      assert_equal bytes, Recordings.playback!(@room, @customer_login)
      outsider = Session.create!(user: create_user("client"))
      assert_raises(Denied) { Recordings.playback!(@room, outsider) }
      Recordings.revoke!(@room, @technician_login)
      assert_nil record.reload.payload
      assert_raises(Denied) { Recordings.playback!(@room, @customer_login) }
    end
  end

  test "rejects audio and expires stored playback" do
    start_recording
    upload_video(audio: true) do |file, _|
      assert_raises(ScreenShare::Conflict) { Recordings.store!(@room, @customer_login, file) }
    end

    upload_video do |file, _|
      recording = Recordings.store!(@room, @customer_login, file)
      recording.update!(expires_at: 1.second.ago)
      assert_raises(Denied) { Recordings.playback!(@room, @customer_login) }
      ItRemoteSupportRecordingExpirationJob.new.perform(recording.id)
      assert_nil recording.reload.payload
    end
  end

  private

  def start_recording
    Recordings.consent!(@room, @customer_login)
    Recordings.consent!(@room, @technician_login)
    @room.update!(display_reported_at: Time.current)
    Recordings.start!(@room, @customer_login)
  end

  def upload_video(audio: false)
    skip "FFmpeg and ffprobe are required for the media fixture" unless
      File.executable?("/usr/bin/ffmpeg") && File.executable?("/usr/bin/ffprobe")

    Tempfile.create(["support-video-test", ".webm"], binmode: true) do |file|
      command = %w[/usr/bin/ffmpeg -y -loglevel error -f lavfi -i color=size=64x64:rate=5]
      command += %w[-f lavfi -i sine=frequency=440 -c:a libopus] if audio
      command += %w[-t 0.4 -c:v libvpx -threads 1]
      assert system(*command, file.path)
      bytes = file.read
      file.rewind
      yield ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "session.webm", type: "video/webm"), bytes
    end
  end

  def create_user(role)
    User.create!(role: role, email_address: "#{SecureRandom.hex(8)}@example.test",
      first_name: "Remote", last_name: "Support", password: SecureRandom.hex(16))
  end
end
