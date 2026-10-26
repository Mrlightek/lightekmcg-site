require "test_helper"
require_relative "../../support/studio_live_test_support"
class StudioLiveDestinationTest < ActiveSupport::TestCase
  def actor(role = "super_admin")
    User.create!(first_name: "Relay", last_name: "Operator", role: role, email_address: "relay-#{SecureRandom.hex(6)}@example.test", password: "Live-test-password-2026!")
  end
  def vault_method(name, implementation)
    original = LightekVault::Service.method(name) if LightekVault::Service.respond_to?(name)
    LightekVault::Service.define_singleton_method(name, implementation)
    yield
  ensure
    if original
      LightekVault::Service.define_singleton_method(name, original)
    else
      LightekVault::Service.singleton_class.remove_method(name)
    end
  end
  test "Restream URLs are accepted only for Restream and reject unsafe destinations" do
    destination = Studio::Live::Destination
    %w[rtmp://live.restream.io/live rtmps://live.restream.io:1935/live rtmps://live.restream.io:443/live/].each do |url|
      server, key = destination.validate!(url, "fixture-key", provider: "restream")
      assert server.end_with?("/")
      assert_equal "fixture-key", key
      assert_raises(destination::Unavailable) { destination.validate!(url, key) }
    end
    %w[http://live.restream.io/live rtmp://127.0.0.1/live rtmp://restream.io.evil.test/live rtmp://evilrestream.io/live rtmp://live.restream.io:22/live rtmp://user:pass@live.restream.io/live rtmp://live.restream.io/live?token=secret rtmp://live.restream.io/live#fragment rtmp://push.tiktok.com/live].each do |url|
      error = assert_raises(destination::Unavailable) { destination.validate!(url, "fixture-key", provider: "restream") }
      refute_includes error.message, "fixture-key"
      refute_includes error.message, url
    end
    assert_raises(destination::Unavailable) { destination.validate!("rtmp://live.restream.io/live", "bad\nkey", provider: "restream") }
    assert_raises(destination::Unavailable) { destination.validate!("rtmp://live.restream.io/live", "", provider: "restream") }
    assert_raises(destination::Unavailable) { destination.validate!("rtmp://live.restream.io/live", "key", provider: "unknown") }
  end
  test "Vault writes and reads remain isolated by operator and provider" do
    user, other = actor, actor
    destination = Studio::Live::Destination
    saved = {}
    test_case = self
    store = ->(**args) do
      test_case.assert_equal [destination::CONSUMER], args[:access_policy]["consumers"]
      test_case.assert_equal [destination::PURPOSE], args[:access_policy]["purposes"]
      saved[args.fetch(:slug)] = args.fetch(:payload)
    end
    vault_method(:store!, store) do
      destination.save!(user: user, server_url: "rtmp://push.tiktok.com/live", stream_key: "direct-key")
      destination.save!(user: user, server_url: "rtmps://live.restream.io:1935/live", stream_key: "relay-key", provider: "restream")
      destination.save!(user: other, server_url: "rtmp://live.restream.io/live", stream_key: "other-key", provider: "restream")
    end
    assert_equal 3, saved.size
    checkout = ->(**args) do
      test_case.assert_equal destination::CONSUMER, args[:consumer]
      test_case.assert_equal destination::PURPOSE, args[:purpose]
      saved.fetch(args.fetch(:slug))
    end
    vault_method(:checkout!, checkout) do
      assert_equal "rtmp://push.tiktok.com/live/direct-key", destination.output!(user)
      assert_equal "rtmps://live.restream.io:1935/live/relay-key", destination.output!(user, provider: "restream")
      assert_equal "rtmp://live.restream.io/live/other-key", destination.output!(other, provider: "restream")
    end
  end
  test "a relay reservation requires configuration and stores only a Vault reference" do
    user = actor
    with_live_stub(Studio::Live::Destination, :configured?, false) do
      assert_raises(Studio::Live::Destination::Unavailable) { Studio::Live::Sessions.create!(user: user, title: "Build", destination: "restream") }
    end
    with_live_stub(Studio::Live::Destination, :configured?, true) do
      with_live_stub(Studio::Live::Encoder, :available?, true) do
        operation = Studio::Live::Sessions.create!(user: user, title: "Build", destination: "restream")
        assert_equal "restream", operation.metadata["destination"]
        assert_equal "tiktok", operation.platform
        assert_equal "studio-live-#{user.id}-restream", operation.credential_ref
        refute operation.metadata.key?("stream_key")
        refute operation.metadata.key?("server_url")
      end
    end
  end
  test "ordinary admin cannot configure Restream and unavailable credentials fail closed" do
    destination = Studio::Live::Destination
    assert_raises(::Gatekeeper::StudioLivePolicy::Denied) { destination.save!(user: actor("admin"), server_url: "rtmp://live.restream.io/live", stream_key: "fixture-key", provider: "restream") }
    vault_method(:checkout!, ->(**_) { raise LightekVault::Service::AccessDenied }) do
      error = assert_raises(destination::Unavailable) { destination.output!(actor, provider: "restream") }
      refute_includes error.message, "fixture-key"
    end
  end
end
