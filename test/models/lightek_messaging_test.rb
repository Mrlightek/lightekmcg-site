# frozen_string_literal: true

require "test_helper"

class LightekMessagingTest <
      ActiveSupport::TestCase

  setup do
    @alice =
      create_profile("alice")

    @bob =
      create_profile("bob")

    @charlie =
      create_profile("charlie")

    @dana =
      create_profile("dana")
  end

  test "direct conversation has exactly two profiles" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    assert_equal(
      "direct",
      conversation.kind
    )

    assert_equal(
      2,
      conversation
        .participants
        .active
        .count
    )

    assert_equal(
      [
        @alice.id,
        @bob.id
      ].sort.join(":"),
      conversation.direct_key
    )
  end

  test "same direct pair reuses one conversation" do
    first =
      start_direct(
        @alice,
        @bob
      )

    second =
      LightekMessaging::
        StartConversation.call(
          creator_profile:
            @bob,
          participant_profile_ids:
            [@alice.id],
          kind: "direct"
        )

    assert_equal(
      first.id,
      second.id
    )
  end

  test "group conversation supports multiple profiles and owner" do
    conversation =
      LightekMessaging::
        StartConversation.call(
          creator_profile:
            @alice,
          participant_profile_ids: [
            @bob.id,
            @charlie.id,
            @dana.id
          ],
          kind: "group",
          title: "Production Crew"
        )

    assert_equal(
      "group",
      conversation.kind
    )

    assert_equal(
      "Production Crew",
      conversation.title
    )

    assert_equal(
      4,
      conversation
        .participants
        .active
        .count
    )

    assert_equal(
      "owner",
      conversation
        .participants
        .find_by!(
          profile_id:
            @alice.id
        )
        .role
    )
  end

  test "group requires three total participants" do
    error =
      assert_raises(
        ArgumentError
      ) do
        LightekMessaging::
          StartConversation.call(
            creator_profile:
              @alice,
            participant_profile_ids:
              [@bob.id],
            kind: "group",
            title: "Too Small"
          )
      end

    assert_match(
      /at least three/,
      error.message
    )
  end

  test "only active participants can send" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    message =
      LightekMessaging::
        SendMessage.call(
          conversation:
            conversation,
          sender_profile:
            @alice,
          body:
            "Welcome to Lightek."
        )

    assert_equal(
      @alice.id,
      message.sender_profile_id
    )

    assert_equal(
      "Welcome to Lightek.",
      message.body
    )

    assert_raises(
      LightekMessaging::
        AccessDenied
    ) do
      LightekMessaging::
        SendMessage.call(
          conversation:
            conversation,
          sender_profile:
            @charlie,
          body:
            "I should not be here."
        )
    end
  end

  test "reply must belong to same conversation" do
    first =
      start_direct(
        @alice,
        @bob
      )

    second =
      start_direct(
        @alice,
        @charlie
      )

    original =
      LightekMessaging::
        SendMessage.call(
          conversation:
            first,
          sender_profile:
            @alice,
          body:
            "First thread"
        )

    reply =
      second.messages.build(
        sender_profile:
          @alice,
        body:
          "Wrong thread",
        reply_to_message:
          original
      )

    assert_not(
      reply.valid?
    )

    assert_includes(
      reply.errors[
        :reply_to_message
      ],
      "must belong to the same conversation"
    )
  end

  test "participant can mark conversation read" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    participant =
      conversation
        .participants
        .find_by!(
          profile_id:
            @bob.id
        )

    assert_nil(
      participant.last_read_at
    )

    participant.mark_read!

    assert_not_nil(
      participant.reload.last_read_at
    )
  end

  private

  def start_direct(first, second)
    LightekMessaging::
      StartConversation.call(
        creator_profile:
          first,
        participant_profile_ids:
          [second.id],
        kind: "direct"
      )
  end

  def create_profile(label)
    user =
      User.create!(
        email_address:
          "#{label}-" \
          "#{SecureRandom.hex(5)}" \
          "@example.test",
        password:
          "Password123!",
        first_name:
          label.capitalize,
        last_name:
          "Messaging"
      )

    user.profile
  end
end
