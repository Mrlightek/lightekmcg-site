require "test_helper"
require_relative "../support/studio_live_test_support"
class StudioBroadcastChannelTest < ActionCable::Channel::TestCase
  tests StudioBroadcastChannel
  def actor(role = "admin")
    User.create!(first_name: "Live", last_name: "Operator", role: role, email_address: "cable-live-#{SecureRandom.hex(6)}@example.test", password: "Live-test-password-2026!")
  end
  def reserve(user)
    with_live_stub(Studio::Live::Encoder, :available?, true) { Studio::Live::Sessions.create!(user: user, title: "Channel test", destination: "test") }
  end
  test "subscription requires an actor bound ticket" do
    user = actor; operation = reserve(user)
    stub_connection current_user: actor
    subscribe ticket: Studio::Live::Sessions.ticket(operation, user)
    assert subscription.rejected?
  end
  test "unsubscribing a replay cannot cancel an active session" do
    user = actor; operation = reserve(user)
    stub_connection current_user: user
    subscribe ticket: Studio::Live::Sessions.ticket(operation, user)
    assert subscription.confirmed?
    operation.update!(status: "live")
    unsubscribe
    assert_equal "live", operation.reload.status
  end
  test "a duplicate start cannot change the original session status" do
    user = actor; operation = reserve(user)
    stub_connection current_user: user
    subscribe ticket: Studio::Live::Sessions.ticket(operation, user)
    operation.update!(status: "live")
    perform :start
    assert_equal "live", operation.reload.status
    assert_equal "failed", transmissions.last["event"]
  end
  test "ordered chunks are acknowledged and stop closes the encoder" do
    user = actor; operation = reserve(user); stub_connection current_user: user
    subscribe ticket: Studio::Live::Sessions.ticket(operation, user)
    encoder = Class.new do
      attr_reader :received, :stopped
      def start! = self
      def append!(encoded:, sequence:)
        @received = [encoded, sequence]
        sequence
      end
      def stop! = @stopped = true
    end.new
    with_live_stub(Studio::Live::Encoder, :new, encoder) do
      perform :start
      assert_equal "ready", transmissions.last["event"]
      perform :chunk, live_chunk: "Zml4dHVyZQ==", sequence: 0
      assert_equal "ack", transmissions.last["event"]
      assert_equal 0, transmissions.last["sequence"]
      perform :stop
    end
    assert_equal ["Zml4dHVyZQ==", 0], encoder.received
    assert encoder.stopped
  end
  test "Restream channel checks out the relay provider at encoder start" do
    user = actor
    operation = with_live_stub(Studio::Live::Destination, :configured?, true) do
      with_live_stub(Studio::Live::Encoder, :available?, true) { Studio::Live::Sessions.create!(user: user, title: "Relay test", destination: "restream") }
    end
    stub_connection current_user: user
    subscribe ticket: Studio::Live::Sessions.ticket(operation, user)
    original = Studio::Live::Destination.method(:output!)
    requested = nil
    Studio::Live::Destination.define_singleton_method(:output!) { |operator, provider:| requested = [operator.id, provider]; "rtmp://live.restream.io/live/fixture-key" }
    encoder = Object.new
    def encoder.start! = self
    def encoder.stop!(**_) = nil
    constructor = Studio::Live::Encoder.method(:new)
    encoded = nil
    Studio::Live::Encoder.define_singleton_method(:new) { |**args| encoded = args; encoder }
    perform :start
    assert_equal [user.id, "restream"], requested
    assert_equal "rtmp://live.restream.io/live/fixture-key", encoded[:output]
    assert_equal false, encoded[:test]
    assert_equal "ready", transmissions.last["event"]
  ensure
    Studio::Live::Destination.define_singleton_method(:output!, original) if original
    Studio::Live::Encoder.define_singleton_method(:new, constructor) if constructor
  end

end
