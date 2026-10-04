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

  test "block prevents both profiles from sending in existing direct conversation" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    LightekSocial::BlockProfile.call(
      blocker_profile:
        @alice.profile,

      blocked_profile:
        @bob.profile,

      reason_code:
        "user_choice"
    )

    alice_show =
      perform(
        "show",
        @alice,
        {
          "conversation_id" =>
            conversation.id
        }
      )

    assert_equal(
      true,
      alice_show
        .fetch(
          "conversation"
        )
        .fetch(
          "messaging_blocked"
        )
    )

    assert_raises(
      LightekMessaging::AccessDenied
    ) do
      perform(
        "send",
        @alice,
        {
          "conversation_id" =>
            conversation.id,

          "body" =>
            "Should not send"
        }
      )
    end

    assert_raises(
      LightekMessaging::AccessDenied
    ) do
      perform(
        "send",
        @bob,
        {
          "conversation_id" =>
            conversation.id,

          "body" =>
            "Should not send either"
        }
      )
    end

    assert_equal(
      0,
      conversation
        .messages
        .count
    )
  end

  test "block prevents starting or reopening a direct conversation" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    LightekSocial::BlockProfile.call(
      blocker_profile:
        @alice.profile,

      blocked_profile:
        @bob.profile,

      reason_code:
        "user_choice"
    )

    assert_raises(
      LightekMessaging::AccessDenied
    ) do
      perform(
        "start",
        @alice,
        {
          "kind" =>
            "direct",

          "participant_profile_ids" =>
            [
              @bob.profile.id
            ]
        }
      )
    end

    assert_raises(
      LightekMessaging::AccessDenied
    ) do
      perform(
        "start",
        @bob,
        {
          "kind" =>
            "direct",

          "participant_profile_ids" =>
            [
              @alice.profile.id
            ]
        }
      )
    end

    assert_equal(
      conversation.id,
      LightekMessaging::Conversation
        .find_by!(
          direct_key:
            [
              @alice.profile.id,
              @bob.profile.id
            ]
              .sort
              .join(":")
        )
        .id
    )
  end

  test "delete direct conversation is scoped to authenticated profile" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    send_from(
      conversation,
      @bob,
      "Shared history"
    )

    perform(
      "delete",
      @alice,
      {
        "conversation_id" =>
          conversation.id
      }
    )

    alice_member =
      conversation
        .participants
        .find_by!(
          profile_id:
            @alice.profile.id
        )

    assert_not(
      alice_member.active?
    )

    alice_ids =
      perform(
        "list",
        @alice
      )
        .fetch(
          "conversations"
        )
        .map do |record|
          record.fetch(
            "id"
          )
        end

    bob_ids =
      perform(
        "list",
        @bob
      )
        .fetch(
          "conversations"
        )
        .map do |record|
          record.fetch(
            "id"
          )
        end

    refute_includes(
      alice_ids,
      conversation.id
    )

    assert_includes(
      bob_ids,
      conversation.id
    )

    assert_equal(
      1,
      conversation
        .messages
        .count
    )
  end

  test "starting a deleted direct conversation reactivates only new visible history" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    old_message =
      send_from(
        conversation,
        @bob,
        "Before deletion"
      )

    perform(
      "delete",
      @alice,
      {
        "conversation_id" =>
          conversation.id
      }
    )

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
            ]
        }
      )

    assert_equal(
      conversation.id,
      result
        .fetch(
          "conversation"
        )
        .fetch(
          "id"
        )
    )

    member =
      conversation
        .participants
        .find_by!(
          profile_id:
            @alice.profile.id
        )

    assert(
      member.reload.active?
    )

    assert_operator(
      member.joined_at,
      :>,
      old_message.created_at
    )

    assert_empty(
      result
        .fetch(
          "conversation"
        )
        .fetch(
          "messages"
        )
    )
  end

  test "new direct message reactivates peer after they deleted conversation" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    send_from(
      conversation,
      @bob,
      "Old history"
    )

    perform(
      "delete",
      @alice,
      {
        "conversation_id" =>
          conversation.id
      }
    )

    perform(
      "send",
      @bob,
      {
        "conversation_id" =>
          conversation.id,

        "body" =>
          "New after deletion"
      }
    )

    alice_member =
      conversation
        .participants
        .find_by!(
          profile_id:
            @alice.profile.id
        )

    assert(
      alice_member.reload.active?
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

    bodies =
      result
        .fetch(
          "conversation"
        )
        .fetch(
          "messages"
        )
        .map do |message|
          message.fetch(
            "body"
          )
        end

    assert_equal(
      [
        "New after deletion"
      ],
      bodies
    )
  end

  test "leave group removes only actor and preserves shared conversation" do
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

    send_from(
      conversation,
      @bob,
      "Group history"
    )

    perform(
      "leave",
      @bob,
      {
        "conversation_id" =>
          conversation.id
      }
    )

    bob_member =
      conversation
        .participants
        .find_by!(
          profile_id:
            @bob.profile.id
        )

    assert_not(
      bob_member.active?
    )

    assert_equal(
      2,
      conversation
        .participants
        .active
        .count
    )

    assert_equal(
      1,
      conversation
        .messages
        .count
    )

    bob_ids =
      perform(
        "list",
        @bob
      )
        .fetch(
          "conversations"
        )
        .map do |record|
          record.fetch(
            "id"
          )
        end

    alice_ids =
      perform(
        "list",
        @alice
      )
        .fetch(
          "conversations"
        )
        .map do |record|
          record.fetch(
            "id"
          )
        end

    refute_includes(
      bob_ids,
      conversation.id
    )

    assert_includes(
      alice_ids,
      conversation.id
    )
  end

  test "group owner transfers ownership when leaving" do
    result =
      perform(
        "start",
        @alice,
        {
          "kind" =>
            "group",

          "title" =>
            "Ownership Test",

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

    perform(
      "leave",
      @alice,
      {
        "conversation_id" =>
          conversation.id
      }
    )

    active_owners =
      conversation
        .participants
        .active
        .where(
          role:
            "owner"
        )

    assert_equal(
      1,
      active_owners.count
    )

    refute_equal(
      @alice.profile.id,
      active_owners
        .first
        .profile_id
    )
  end

  test "delete and leave enforce conversation kind" do
    direct =
      start_direct(
        @alice,
        @bob
      )

    group_result =
      perform(
        "start",
        @alice,
        {
          "kind" =>
            "group",

          "title" =>
            "Kind Test",

          "participant_profile_ids" =>
            [
              @bob.profile.id,
              @charlie.profile.id
            ]
        }
      )

    group =
      LightekMessaging::
        Conversation.find(
          group_result
            .fetch(
              "conversation"
            )
            .fetch(
              "id"
            )
        )

    assert_raises(
      ArgumentError
    ) do
      perform(
        "leave",
        @alice,
        {
          "conversation_id" =>
            direct.id
        }
      )
    end

    assert_raises(
      ArgumentError
    ) do
      perform(
        "delete",
        @alice,
        {
          "conversation_id" =>
            group.id
        }
      )
    end
  end

  test "deleted direct list preview respects fresh joined at boundary" do
    conversation =
      start_direct(
        @alice,
        @bob
      )

    send_from(
      conversation,
      @bob,
      "Old preview"
    )

    perform(
      "delete",
      @alice,
      {
        "conversation_id" =>
          conversation.id
      }
    )

    perform(
      "start",
      @alice,
      {
        "kind" =>
          "direct",

        "participant_profile_ids" =>
          [
            @bob.profile.id
          ]
      }
    )

    reopened =
      perform(
        "list",
        @alice
      )
        .fetch(
          "conversations"
        )
        .find do |record|
          record.fetch(
            "id"
          ) ==
            conversation.id
        end

    assert_nil(
      reopened.fetch(
        "last_message"
      )
    )

    assert_nil(
      reopened.fetch(
        "last_message_at"
      )
    )

    perform(
      "send",
      @alice,
      {
        "conversation_id" =>
          conversation.id,

        "body" =>
          "New preview"
      }
    )

    refreshed =
      perform(
        "list",
        @alice
      )
        .fetch(
          "conversations"
        )
        .find do |record|
          record.fetch(
            "id"
          ) ==
            conversation.id
        end

    assert_equal(
      "New preview",
      refreshed
        .fetch(
          "last_message"
        )
        .fetch(
          "body"
        )
    )
  end

  test "owner and admin can add while former member rejoins as member" do
    result =
      perform(
        "start",
        @alice,
        {
          "kind" =>
            "group",

          "title" =>
            "Governance Add Test",

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

    old_message =
      send_from(
        conversation,
        @alice,
        "Before leave"
      )

    perform(
      "leave",
      @bob,
      {
        "conversation_id" =>
          conversation.id
      }
    )

    perform(
      "group_add_members",
      @alice,
      {
        "conversation_id" =>
          conversation.id,

        "profile_ids" =>
          [
            @bob.profile.id,
            @dana.profile.id
          ]
      }
    )

    bob_member =
      conversation
        .participants
        .find_by!(
          profile_id:
            @bob.profile.id
        )

    assert(
      bob_member.reload.active?
    )

    assert_equal(
      "member",
      bob_member.role
    )

    assert_operator(
      bob_member.joined_at,
      :>,
      old_message.created_at
    )

    assert(
      conversation
        .participants
        .find_by!(
          profile_id:
            @dana.profile.id
        )
        .active?
    )

    bob_show =
      perform(
        "show",
        @bob,
        {
          "conversation_id" =>
            conversation.id
        }
      )

    assert_empty(
      bob_show
        .fetch(
          "conversation"
        )
        .fetch(
          "messages"
        )
    )
  end

  test "owner can promote and demote administrator" do
    result =
      perform(
        "start",
        @alice,
        {
          "kind" =>
            "group",

          "title" =>
            "Role Test",

          "participant_profile_ids" =>
            [
              @bob.profile.id,
              @charlie.profile.id
            ]
        }
      )

    conversation_id =
      result
        .fetch(
          "conversation"
        )
        .fetch(
          "id"
        )

    promoted =
      perform(
        "group_promote_admin",
        @alice,
        {
          "conversation_id" =>
            conversation_id,

          "profile_id" =>
            @bob.profile.id
        }
      )

    assert_equal(
      "admin",
      promoted
        .fetch(
          "participant"
        )
        .fetch(
          "role"
        )
    )

    demoted =
      perform(
        "group_demote_admin",
        @alice,
        {
          "conversation_id" =>
            conversation_id,

          "profile_id" =>
            @bob.profile.id
        }
      )

    assert_equal(
      "member",
      demoted
        .fetch(
          "participant"
        )
        .fetch(
          "role"
        )
    )
  end

  test "admin can add and remove regular member but cannot manage privileged members" do
    result =
      perform(
        "start",
        @alice,
        {
          "kind" =>
            "group",

          "title" =>
            "Admin Permissions",

          "participant_profile_ids" =>
            [
              @bob.profile.id,
              @charlie.profile.id
            ]
        }
      )

    conversation_id =
      result
        .fetch(
          "conversation"
        )
        .fetch(
          "id"
        )

    perform(
      "group_promote_admin",
      @alice,
      {
        "conversation_id" =>
          conversation_id,

        "profile_id" =>
          @bob.profile.id
      }
    )

    perform(
      "group_add_members",
      @bob,
      {
        "conversation_id" =>
          conversation_id,

        "profile_ids" =>
          [
            @dana.profile.id
          ]
      }
    )

    removed =
      perform(
        "group_remove_member",
        @bob,
        {
          "conversation_id" =>
            conversation_id,

          "profile_id" =>
            @dana.profile.id
        }
      )

    assert_equal(
      @dana.profile.id,
      removed.fetch(
        "removed_profile_id"
      )
    )

    assert_raises(
      LightekMessaging::AccessDenied
    ) do
      perform(
        "group_remove_member",
        @bob,
        {
          "conversation_id" =>
            conversation_id,

          "profile_id" =>
            @alice.profile.id
        }
      )
    end

    perform(
      "group_promote_admin",
      @alice,
      {
        "conversation_id" =>
          conversation_id,

        "profile_id" =>
          @charlie.profile.id
      }
    )

    assert_raises(
      LightekMessaging::AccessDenied
    ) do
      perform(
        "group_remove_member",
        @bob,
        {
          "conversation_id" =>
            conversation_id,

          "profile_id" =>
            @charlie.profile.id
        }
      )
    end
  end

  test "owner can remove administrator and removed member stays inactive during future messages" do
    result =
      perform(
        "start",
        @alice,
        {
          "kind" =>
            "group",

          "title" =>
            "Owner Removal",

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

    perform(
      "group_promote_admin",
      @alice,
      {
        "conversation_id" =>
          conversation.id,

        "profile_id" =>
          @bob.profile.id
      }
    )

    perform(
      "group_remove_member",
      @alice,
      {
        "conversation_id" =>
          conversation.id,

        "profile_id" =>
          @bob.profile.id
      }
    )

    bob_member =
      conversation
        .participants
        .find_by!(
          profile_id:
            @bob.profile.id
        )

    refute(
      bob_member.reload.active?
    )

    send_from(
      conversation,
      @alice,
      "After removal"
    )

    refute(
      bob_member.reload.active?
    )

    bob_ids =
      perform(
        "list",
        @bob
      )
        .fetch(
          "conversations"
        )
        .map do |record|
          record.fetch(
            "id"
          )
        end

    refute_includes(
      bob_ids,
      conversation.id
    )
  end

  test "ordinary member cannot add remove promote or demote" do
    result =
      perform(
        "start",
        @alice,
        {
          "kind" =>
            "group",

          "title" =>
            "Member Permissions",

          "participant_profile_ids" =>
            [
              @bob.profile.id,
              @charlie.profile.id
            ]
        }
      )

    conversation_id =
      result
        .fetch(
          "conversation"
        )
        .fetch(
          "id"
        )

    assert_raises(
      LightekMessaging::AccessDenied
    ) do
      perform(
        "group_add_members",
        @bob,
        {
          "conversation_id" =>
            conversation_id,

          "profile_ids" =>
            [
              @dana.profile.id
            ]
        }
      )
    end

    assert_raises(
      LightekMessaging::AccessDenied
    ) do
      perform(
        "group_remove_member",
        @bob,
        {
          "conversation_id" =>
            conversation_id,

          "profile_id" =>
            @charlie.profile.id
        }
      )
    end

    assert_raises(
      LightekMessaging::AccessDenied
    ) do
      perform(
        "group_promote_admin",
        @bob,
        {
          "conversation_id" =>
            conversation_id,

          "profile_id" =>
            @charlie.profile.id
        }
      )
    end

    assert_raises(
      LightekMessaging::AccessDenied
    ) do
      perform(
        "group_demote_admin",
        @bob,
        {
          "conversation_id" =>
            conversation_id,

          "profile_id" =>
            @charlie.profile.id
        }
      )
    end
  end

  test "same group title and same people still creates distinct conversations" do
    payload = {
      "kind" =>
        "group",

      "title" =>
        "Same Name Is Not Identity",

      "participant_profile_ids" =>
        [
          @bob.profile.id,
          @charlie.profile.id
        ]
    }

    first =
      perform(
        "start",
        @alice,
        payload
      )
        .fetch(
          "conversation"
        )
        .fetch(
          "id"
        )

    second =
      perform(
        "start",
        @alice,
        payload
      )
        .fetch(
          "conversation"
        )
        .fetch(
          "id"
        )

    refute_equal(
      first,
      second
    )
  end

  test "Nevaeh resolves group governance contracts" do
    controller =
      Api::NevaehController.new

    expected = {
      "messages.group.add_members" =>
        [
          "messages.group.add_members.requested",
          "group_add_members"
        ],

      "messages.group.remove_member" =>
        [
          "messages.group.remove_member.requested",
          "group_remove_member"
        ],

      "messages.group.promote_admin" =>
        [
          "messages.group.promote_admin.requested",
          "group_promote_admin"
        ],

      "messages.group.demote_admin" =>
        [
          "messages.group.demote_admin.requested",
          "group_demote_admin"
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
