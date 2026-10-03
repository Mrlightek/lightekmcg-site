# frozen_string_literal: true

require "test_helper"

class LightekMessagingPwaWorkerTest <
      ActiveSupport::TestCase

  setup do
    @alice =
      create_user(
        "alice"
      )

    @bob =
      create_user(
        "bob"
      )

    @charlie =
      create_user(
        "charlie"
      )

    @dana =
      create_user(
        "dana"
      )
  end

  test "list returns only conversations for authenticated profile" do
    mine =
      start_direct(
        @alice,
        @bob
      )

    other =
      start_direct(
        @charlie,
        @dana
      )

    send_from(
      mine,
      @bob,
      "For Alice"
    )

    send_from(
      other,
      @charlie,
      "Not for Alice"
    )

    result =
      perform(
        "list",
        @alice
      )

    ids =
      result
        .fetch(
          "conversations"
        )
        .map do |record|
          record.fetch(
            "id"
          )
        end

    assert_equal(
      [mine.id],
      ids
    )
  end

  test "start direct derives creator from authenticated user" do
    result =
      perform(
        "start",
        @alice,
        {
          "kind" =>
            "direct",

          "participant_profile_ids" =>
            [
              @bob.profile.id
            ],

          "creator_profile_id" =>
            @charlie.profile.id
        }
      )

    conversation =
      LightekMessaging::
        Conversation.find(
          result
            .fetch(
              "conversation"
            )
            .fetch(
              "id"
            )
        )

    assert_equal(
      @alice.profile.id,
      conversation
        .created_by_profile_id
    )

    assert_equal(
      [
        @alice.profile.id,
        @bob.profile.id
      ].sort,
      conversation
        .profiles
        .pluck(:id)
        .sort
    )
  end

  test "start group creates owner plus multiple members" do
    result =
      perform(
        "start",
        @alice,
        {
          "kind" =>
            "group",

          "title" =>
            "Production Crew",

          "participant_profile_ids" =>
            [
              @bob.profile.id,
              @charlie.profile.id
            ]
        }
      )

    conversation =
      LightekMessaging::
        Conversation.find(
          result
            .fetch(
              "conversation"
            )
            .fetch(
              "id"
            )
        )

    assert_equal(
      "group",
      conversation.kind
    )

    assert_equal(
      3,
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
            @alice.profile.id
        )
        .role
    )
  end

  test "show denies profiles outside conversation" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    assert_raises(
      LightekMessaging::
        AccessDenied
    ) do
      perform(
        "show",
        @charlie,
        {
          "conversation_id" =>
            conversation.id
        }
      )
    end
  end

  test "send always uses authenticated profile as sender" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    result =
      perform(
        "send",
        @alice,
        {
          "conversation_id" =>
            conversation.id,

          "body" =>
            "Authenticated sender",

          "sender_profile_id" =>
            @charlie.profile.id
        }
      )

    message =
      LightekMessaging::
        Message.find(
          result
            .fetch(
              "message"
            )
            .fetch(
              "id"
            )
        )

    assert_equal(
      @alice.profile.id,
      message.sender_profile_id
    )

    assert_equal(
      @alice.profile.display_handle,
      result
        .fetch(
          "message"
        )
        .fetch(
          "sender"
        )
        .fetch(
          "display_handle"
        )
    )
  end

  test "mark read clears unread messages for authenticated profile" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    send_from(
      conversation,
      @bob,
      "Unread"
    )

    before =
      perform(
        "list",
        @alice
      )
        .fetch(
          "conversations"
        )
        .first
        .fetch(
          "unread_count"
        )

    assert_equal(
      1,
      before
    )

    result =
      perform(
        "mark_read",
        @alice,
        {
          "conversation_id" =>
            conversation.id
        }
      )

    assert_equal(
      0,
      result.fetch(
        "unread_count"
      )
    )

    assert_not_nil(
      conversation
        .participants
        .find_by!(
          profile_id:
            @alice.profile.id
        )
        .reload
        .last_read_at
    )
  end

  test "payload exposes public profile identity only" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    result =
      perform(
        "show",
        @alice,
        {
          "conversation_id" =>
            conversation.id
        }
      )

    profile_payload =
      result
        .fetch(
          "conversation"
        )
        .fetch(
          "participants"
        )
        .first
        .fetch(
          "profile"
        )

    assert_equal(
      %w[
        avatar_url
        display_handle
        id
        name
        profile_type
      ],
      profile_payload
        .keys
        .sort
    )

    assert_not_includes(
      profile_payload.values,
      @alice.email_address
    )
  end

  test "people returns searchable public profiles and excludes self" do
    @bob.profile.update!(
      display_name:
        "Bob Public"
    )

    result =
      perform(
        "people",
        @alice,
        {
          "query" =>
            "Bob Public"
        }
      )

    profiles =
      result.fetch(
        "profiles"
      )

    assert_equal(
      [
        @bob.profile.id
      ],
      profiles.map do |record|
        record.fetch(
          "id"
        )
      end
    )

    profile_payload =
      profiles.first

    assert_equal(
      %w[
        avatar_url
        display_handle
        id
        name
        profile_type
      ],
      profile_payload
        .keys
        .sort
    )

    assert_not_includes(
      profile_payload.values,
      @bob.email_address
    )

    assert_not_includes(
      profiles.map do |record|
        record.fetch(
          "id"
        )
      end,
      @alice.profile.id
    )
  end

  test "Nevaeh controller resolves all messaging contracts" do
    controller =
      Api::NevaehController.new

    expected = {
      "messages.people" =>
        [
          "messages.people.requested",
          "people"
        ],

      "messages.list" =>
        [
          "messages.list.requested",
          "list"
        ],

      "messages.show" =>
        [
          "messages.show.requested",
          "show"
        ],

      "messages.start" =>
        [
          "messages.start.requested",
          "start"
        ],

      "messages.send" =>
        [
          "messages.send.requested",
          "send"
        ],

      "messages.mark_read" =>
        [
          "messages.mark_read.requested",
          "mark_read"
        ]
    }

    expected.each do |slug, values|
      assert_equal(
        values.fetch(0),
        controller.send(
          :resolve_event_type!,
          slug
        )
      )

      assert_equal(
        values.fetch(1),
        controller.send(
          :resolve_worker_action!,
          slug
        )
      )
    end
  end

  private

  def perform(
    action,
    user,
    extra = {}
  )
    LightekMessaging::
      Workers::
      Pwa.perform(
        action,
        extra.merge(
          "user_id" =>
            user.id
        )
      )
  end

  def start_direct(first, second)
    LightekMessaging::
      StartConversation.call(
        creator_profile:
          first.profile,

        participant_profile_ids:
          [
            second.profile.id
          ],

        kind:
          "direct"
      )
  end

  def send_from(
    conversation,
    user,
    body
  )
    LightekMessaging::
      SendMessage.call(
        conversation:
          conversation,

        sender_profile:
          user.profile,

        body:
          body
      )
  end

  def create_user(label)
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
  end
end
