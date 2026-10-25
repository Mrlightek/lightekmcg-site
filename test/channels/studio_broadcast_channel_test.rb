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
end
