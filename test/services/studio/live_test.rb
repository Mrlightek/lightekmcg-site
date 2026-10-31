require "test_helper"
require_relative "../../support/studio_live_test_support"
class StudioLiveTest < ActiveSupport::TestCase
  def actor(role = "admin")
    User.create!(first_name: "Live", last_name: "Operator", role: role, email_address: "live-#{SecureRandom.hex(6)}@example.test", password: "Live-test-password-2026!")
  end
  def create_session(user)
    with_live_stub(Studio::Live::Encoder, :available?, true) { Studio::Live::Sessions.create!(user: user, title: "Build session", destination: "test") }
  end
  test "test sessions belong to their operator and carry no credentials" do
    user = actor; operation = create_session(user)
    assert_equal "draft", operation.status
    assert_equal "test", operation.metadata["destination"]
    assert_nil operation.credential_ref
    assert_equal operation.id, Studio::Live::Sessions.find!(operation.id, user).id
    assert_raises(::Gatekeeper::StudioLivePolicy::Denied) { Studio::Live::Sessions.find!(operation.id, actor) }
    assert_equal operation.id, Studio::Live::Sessions.find!(operation.id, actor("super_admin")).id
  end
  test "clients cannot reserve broadcasts and owners cannot reserve twice" do
    assert_raises(::Gatekeeper::StudioLivePolicy::Denied) { create_session(actor("client")) }
    user = actor; create_session(user)
    assert_raises(Studio::Live::Sessions::Busy) { create_session(user) }
  end
  test "global capacity and stale reservations are bounded" do
    first = create_session(actor); create_session(actor)
    assert_raises(Studio::Live::Sessions::Busy) { create_session(actor) }
    first.update_column(:updated_at, 2.minutes.ago)
    assert create_session(actor).persisted?
    assert_equal "failed", first.reload.status
  end
  test "tickets are actor bound expire and reject tampering" do
    user = actor; operation = create_session(user); ticket = Studio::Live::Sessions.ticket(operation, user)
    assert_equal operation.id, Studio::Live::Sessions.from_ticket!(ticket, user).id
    assert_raises(::Gatekeeper::StudioLivePolicy::Denied) { Studio::Live::Sessions.from_ticket!(ticket, actor) }
    assert_raises(::Gatekeeper::StudioLivePolicy::Denied) { Studio::Live::Sessions.from_ticket!(ticket + "x", user) }
    travel 3.minutes do
      assert_raises(::Gatekeeper::StudioLivePolicy::Denied) { Studio::Live::Sessions.from_ticket!(ticket, user) }
    end
  end
  test "late encoder events never revive a completed session" do
    operation = create_session(actor); operation.update!(status: "connecting")
    Studio::Live::Sessions.event!(operation, "sending")
    assert_equal "live", operation.reload.status
    Studio::Live::Sessions.event!(operation, "ended")
    Studio::Live::Sessions.event!(operation, "sending")
    assert_equal "ended", operation.reload.status
    assert operation.ended_at
  end
  test "destination validates platform hostname scheme and key without echoing secrets" do
    server, key = Studio::Live::Destination.validate!("rtmps://push.example.tiktok.com/live/", "fixture-secret")
    assert_equal "rtmps://push.example.tiktok.com/live/", server
    assert_equal "fixture-secret", key
    assert_equal "rtmps://push-rtmp-l1.tiktokcdn.com:443/game/", Studio::Live::Destination.validate!("rtmps://push-rtmp-l1.tiktokcdn.com:443/game/", "fixture-key").first
    ["file:///tmp/capture", "http://127.0.0.1", "rtmp://tiktok.com.evil.test/live/", "rtmp://user:pass@push.tiktok.com/live/", "rtmp://push.tiktok.com:22/live/"].each do |url|
      error = assert_raises(Studio::Live::Destination::Unavailable) { Studio::Live::Destination.validate!(url, "fixture-secret") }
      refute_includes error.message, "fixture-secret"
    end
    assert_raises(Studio::Live::Destination::Unavailable) { Studio::Live::Destination.validate!(server, "") }
    assert_raises(Studio::Live::Destination::Unavailable) { Studio::Live::Destination.validate!(server, "bad\nkey") }
  end
  test "unentitled clients cannot configure a destination" do
    assert_raises(::Gatekeeper::StudioLivePolicy::Denied) { Studio::Live::Destination.save!(user: actor("client"), server_url: "", stream_key: "") }
  end
  test "no configured destination prevents a TikTok reservation" do
    with_live_stub(Studio::Live::Destination, :configured?, false) do
      assert_raises(Studio::Live::Destination::Unavailable) { Studio::Live::Sessions.create!(user: actor, title: "Test", destination: "tiktok") }
    end
  end
  test "media and tickets are redacted from connection logs" do
    output = StringIO.new
    logger = Studio::Live::LogRedaction::SafeLogger.new(Logger.new(output))
    logger.error('unrecognized command live_chunk=fixture-media')
    logger.info('StudioBroadcastChannel ticket=fixture-ticket')
    logger.info('Ordinary connection message')
    refute_includes output.string, "fixture-media"
    refute_includes output.string, "fixture-ticket"
    assert_includes output.string, "Ordinary connection message"
  end
end
