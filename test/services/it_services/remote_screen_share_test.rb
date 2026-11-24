require "test_helper"

class ItServicesRemoteScreenShareTest < ActiveSupport::TestCase
  ScreenShare = ItServices::RemoteScreenShare
  Denied = Gatekeeper::ItRemoteSupportPolicy::Denied
  OFFER = "v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=sendonly\r\n"
  ANSWER = "v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=recvonly\r\n"

  setup do
    skip "Batch B IT Service Requests migration is required" unless ItRemoteSupportSession.available?

    @customer = create_user("client")
    @technician = create_user("contractor")
    @customer_login = Session.create!(user: @customer)
    @technician_login = Session.create!(user: @technician, mfa_verified_at: Time.current)
    LightekIdentity::Factor.create!(user: @technician, enabled_at: Time.current, secret_box: {})
    @work = ItServiceRequest.create!(user: @customer, technician: @technician, service_code: "computer_repair",
      status: "in_progress", delivery_mode: "remote", description: "Inspect a computer issue with the customer.")
  end

  test "negotiates one view-only connection and clears signaling when the customer revokes" do
    room = ScreenShare.request!(@work, @technician_login)
    assert_raises(Denied) { ScreenShare.exchange!(room, @technician_login, nil) }
    assert_raises(Denied) { ScreenShare.approve!(room, @technician_login) }
    ScreenShare.approve!(room, @customer_login)

    assert_nil ScreenShare.exchange!(room, @customer_login, OFFER).fetch(:sdp)
    refute_equal OFFER, room.reload.offer_sdp
    assert_equal OFFER, ScreenShare.exchange!(room, @technician_login, ANSWER).fetch(:sdp)
    assert_equal ANSWER, ScreenShare.exchange!(room, @customer_login, nil).fetch(:sdp)
    assert_raises(ScreenShare::Conflict) { ScreenShare.exchange!(room, @customer_login, OFFER) }

    other_customer_login = Session.create!(user: @customer)
    assert_raises(Denied) { ScreenShare.exchange!(room, other_customer_login, nil) }
    ScreenShare.end!(room, other_customer_login)
    assert_raises(Denied) { ScreenShare.exchange!(room, @technician_login, nil) }
    assert_equal "customer revoked access", room.reload.end_reason
    assert_nil room.offer_sdp
    assert_nil room.answer_sdp
    assert_equal 5, ItServiceEvent.where(it_service_request: @work).count
  end

  test "denies unrelated users, delegated logins, and technicians with stale MFA" do
    outsider = Session.create!(user: create_user("client"))
    assert_raises(Denied) { ScreenShare.request!(@work, outsider) }
    @technician_login.update!(mfa_verified_at: 13.hours.ago)
    assert_raises(Denied) { ScreenShare.request!(@work, @technician_login) }
    @technician_login.update!(mfa_verified_at: Time.current, connect_delegation: {"origin" => "test"})
    assert_raises(Denied) { ScreenShare.request!(@work, @technician_login) }
  end

  test "rejects additional sessions, data channels and reversed media direction" do
    room = ScreenShare.request!(@work, @technician_login)
    assert_raises(ScreenShare::Conflict) { ScreenShare.request!(@work, @technician_login) }
    ScreenShare.approve!(room, @customer_login)
    assert_raises(ScreenShare::Conflict) do
      ScreenShare.exchange!(room, @customer_login, OFFER + "m=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n")
    end
    assert_raises(ScreenShare::Conflict) { ScreenShare.exchange!(room, @customer_login, ANSWER) }
    assert_raises(ScreenShare::Conflict) { ScreenShare.exchange!(room, @technician_login, ANSWER) }
    assert_nil room.reload.offer_sdp
  end

  test "checks expiry, logout and case reassignment before exchanging signals" do
    room = ScreenShare.request!(@work, @technician_login)
    ScreenShare.approve!(room, @customer_login)
    @work.update!(technician: create_user("contractor"))
    assert_raises(Denied) { ScreenShare.exchange!(room, @customer_login, nil) }
    @work.update!(technician: @technician)
    @technician_login.destroy!
    assert_raises(Denied) { ScreenShare.exchange!(room, @customer_login, nil) }
    room.update!(expires_at: 1.second.ago)
    assert_raises(Denied) { ScreenShare.exchange!(room, @customer_login, nil) }
    ScreenShare.expire!(room)
    assert_equal "authorization expired", room.reload.end_reason
  end

  private

  def create_user(role)
    User.create!(role: role, email_address: "#{SecureRandom.hex(8)}@example.test", first_name: "Remote",
      last_name: "Support", password: SecureRandom.hex(16))
  end
end
