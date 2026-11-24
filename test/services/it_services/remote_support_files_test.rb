require "test_helper"
require "tempfile"

class ItServicesRemoteSupportFilesTest < ActiveSupport::TestCase
  Files = ItServices::RemoteSupportFiles
  ScreenShare = ItServices::RemoteScreenShare
  Scanner = ItServices::RemoteSupportFileScanner

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

  test "requires a clean scan and recipient acceptance and delivers verified bytes only once" do
    transfer = offer("sample.log", "log content")
    assert_not_includes transfer.payload, "log content"
    assert_raises(ScreenShare::Conflict) { Files.accept!(@room, @customer_login, transfer.id) }

    Scanner.stub(:clean?, true) { Files.scan!(transfer) }
    assert_equal "awaiting_acceptance", transfer.reload.state
    assert_raises(Gatekeeper::ItRemoteSupportPolicy::Denied) { Files.accept!(@room, @technician_login, transfer.id) }
    outsider_login = Session.create!(user: create_user("client"))
    assert_raises(Gatekeeper::ItRemoteSupportPolicy::Denied) { Files.accept!(@room, outsider_login, transfer.id) }
    Files.accept!(@room, @customer_login, transfer.id)

    assert_raises(Gatekeeper::ItRemoteSupportPolicy::Denied) { Files.download!(@room, @technician_login, transfer.id) }
    download = Files.download!(@room, @customer_login, transfer.id)
    assert_equal "log content", download.fetch(:bytes)
    assert_equal Digest::SHA256.hexdigest("log content"), download.fetch(:sha256)
    assert_nil transfer.reload.payload
    assert_raises(Gatekeeper::ItRemoteSupportPolicy::Denied) { Files.download!(@room, @customer_login, transfer.id) }
  end

  test "fails closed when scanner is unavailable or finds malware" do
    detected = offer("detected.txt", "quarantine test")
    Scanner.stub(:clean?, false) { Files.scan!(detected) }
    assert_equal "quarantined", detected.reload.state
    assert_nil detected.payload

    interrupted = offer("interrupted.txt", "scanner outage test")
    Scanner.stub(:clean?, ->(_) { raise Scanner::Unavailable }) { Files.scan!(interrupted) }
    assert_equal "scan_failed", interrupted.reload.state
    assert_nil interrupted.payload
  end

  test "rejects path-like names, disallowed content and oversized uploads" do
    assert_raises(ScreenShare::Conflict) { offer("bad..name.txt", "text") }
    assert_raises(ScreenShare::Conflict) { offer("binary.txt", "abc\x00def") }
    assert_raises(ScreenShare::Conflict) { offer("wrong.png", "not an image") }
    assert_raises(ScreenShare::Conflict) { offer("large.log", "a" * (Files::MAX_BYTES + 1)) }
    assert_empty @room.transfers
  end

  test "session revocation erases pending files and a later scan cannot release them" do
    offered = offer("pending.txt", "in progress")
    accepted = offer("approved.txt", "in progress")
    Scanner.stub(:clean?, true) { Files.scan!(accepted) }
    Files.accept!(@room, @customer_login, accepted.id)

    ScreenShare.end!(@room, @customer_login)
    assert_raises(Gatekeeper::ItRemoteSupportPolicy::Denied) { Files.download!(@room, @customer_login, accepted.id) }
    Files.scan!(offered)
    assert_equal ["cancelled", "cancelled"], @room.transfers.order(:id).pluck(:state)
    assert_equal [nil, nil], @room.transfers.order(:id).pluck(:payload)
  end

  test "post-scan tampering cannot deliver bytes" do
    transfer = offer("tamper.txt", "original")
    Scanner.stub(:clean?, true) { Files.scan!(transfer) }
    Files.accept!(@room, @customer_login, transfer.id)
    transfer.update!(sha256: Digest::SHA256.hexdigest("different"))
    assert_raises(ScreenShare::Conflict) { Files.download!(@room, @customer_login, transfer.id) }
  end

  private

  def offer(name, content)
    Tempfile.create do |file|
      file.binmode
      file.write(content)
      file.rewind
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: name)
      Scanner.stub(:port, 3310) { Files.offer!(@room, @technician_login, upload) }
    end
  end

  def create_user(role)
    User.create!(role: role, email_address: "#{SecureRandom.hex(8)}@example.test", first_name: "Remote",
      last_name: "Support", password: SecureRandom.hex(16))
  end
end
