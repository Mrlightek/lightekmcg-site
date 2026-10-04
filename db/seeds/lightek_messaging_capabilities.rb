# frozen_string_literal: true

capabilities = [
  {
    name: "Messages People",
    slug: "messages.people",
    intent_name: "find_message_people",
    description:
      "Find public Lightek profiles available for a new conversation.",
    event_type:
      "messages.people.requested"
  },

  {
    name: "Messages List",
    slug: "messages.list",
    intent_name: "list_messages",
    description:
      "List conversations available to the authenticated Lightek profile.",
    event_type:
      "messages.list.requested"
  },

  {
    name: "Messages Show",
    slug: "messages.show",
    intent_name: "show_messages_conversation",
    description:
      "Show one conversation available to the authenticated Lightek profile.",
    event_type:
      "messages.show.requested"
  },

  {
    name: "Messages Start",
    slug: "messages.start",
    intent_name: "start_messages_conversation",
    description:
      "Start a direct or group conversation as the authenticated Lightek profile.",
    event_type:
      "messages.start.requested"
  },

  {
    name: "Messages Send",
    slug: "messages.send",
    intent_name: "send_message",
    description:
      "Send a message as the authenticated Lightek profile.",
    event_type:
      "messages.send.requested"
  },

  {
    name: "Messages Delete",
    slug: "messages.delete",
    intent_name:
      "delete_messages_conversation_for_me",
    description:
      "Remove a direct conversation from the authenticated profile without deleting shared history.",
    event_type:
      "messages.delete.requested"
  },

  {
    name: "Messages Leave",
    slug: "messages.leave",
    intent_name:
      "leave_messages_group",
    description:
      "Leave a group conversation as the authenticated profile without deleting the conversation for remaining members.",
    event_type:
      "messages.leave.requested"
  },

  {
    name:
      "Messages Group Add Members",
    slug:
      "messages.group.add_members",
    intent_name:
      "add_members_to_messages_group",
    description:
      "Add or re-add profiles to an existing group conversation as an authorized owner or administrator.",
    event_type:
      "messages.group.add_members.requested"
  },

  {
    name:
      "Messages Group Remove Member",
    slug:
      "messages.group.remove_member",
    intent_name:
      "remove_member_from_messages_group",
    description:
      "Remove an active profile from a group conversation according to group governance permissions.",
    event_type:
      "messages.group.remove_member.requested"
  },

  {
    name:
      "Messages Group Promote Admin",
    slug:
      "messages.group.promote_admin",
    intent_name:
      "promote_messages_group_admin",
    description:
      "Promote an active regular group member to administrator as the group owner.",
    event_type:
      "messages.group.promote_admin.requested"
  },

  {
    name:
      "Messages Group Demote Admin",
    slug:
      "messages.group.demote_admin",
    intent_name:
      "demote_messages_group_admin",
    description:
      "Demote an active group administrator back to regular member as the group owner.",
    event_type:
      "messages.group.demote_admin.requested"
  },

  {
    name: "Messages Mark Read",
    slug: "messages.mark_read",
    intent_name: "mark_messages_read",
    description:
      "Mark a conversation read for the authenticated Lightek profile.",
    event_type:
      "messages.mark_read.requested"
  }
].freeze

capabilities.each do |definition|
  capability =
    NevaehCapability
      .find_or_initialize_by(
        slug:
          definition.fetch(
            :slug
          )
      )

  capability.assign_attributes(
    name:
      definition.fetch(
        :name
      ),

    domain:
      "messages",

    description:
      definition.fetch(
        :description
      ),

    intent_name:
      definition.fetch(
        :intent_name
      ),

    subject_type:
      nil,

    handler:
      "LightekMessaging::Workers::Pwa",

    queue:
      "default",

    priority:
      5,

    gatekeeper_capability:
      definition.fetch(
        :slug
      ),

    intent_patterns:
      [],

    expected_outcome:
      {},

    failure_policy: {
      "retries" => 1,
      "escalate" => true
    },

    realtime:
      {},

    input_adapter:
      {},

    metadata: {
      "surface" =>
        "messages"
    },

    knowledge_article_ids:
      [],

    event_types: [
      definition.fetch(
        :event_type
      )
    ],

    enabled:
      true
  )

  capability.save!
end

puts(
  "Lightek Messaging capabilities seeded: " \
  "#{capabilities.length}"
)
