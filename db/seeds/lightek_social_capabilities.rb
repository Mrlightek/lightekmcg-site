# frozen_string_literal: true

capabilities = [
  {
    name:
      "Social People Recommend",
    slug:
      "social.people.recommend",
    intent_name:
      "recommend_social_people",
    description:
      "Recommend public Lightek profiles using the authenticated profile's relationship graph with explainable context.",
    event_type:
      "social.people.recommend.requested"
  },

  {
    name:
      "Social Relationship Context",
    slug:
      "social.relationship.context",
    intent_name:
      "show_social_relationship_context",
    description:
      "Show the authenticated profile's private relationship context with another public Lightek profile.",
    event_type:
      "social.relationship.context.requested"
  },

  {
    name:
      "Social Connection Opportunities",
    slug:
      "social.connection.opportunities",
    intent_name:
      "list_social_connection_opportunities",
    description:
      "List relationship-maintenance opportunities already identified for the authenticated Lightek profile.",
    event_type:
      "social.connection.opportunities.requested"
  },

  {
    name:
      "Social Follow",
    slug:
      "social.follow",
    intent_name:
      "follow_social_profile",
    description:
      "Follow another Lightek profile as the authenticated profile.",
    event_type:
      "social.follow.requested"
  },

  {
    name:
      "Social Unfollow",
    slug:
      "social.unfollow",
    intent_name:
      "unfollow_social_profile",
    description:
      "Stop following another Lightek profile as the authenticated profile.",
    event_type:
      "social.unfollow.requested"
  },

  {
    name:
      "Social Blocks List",
    slug:
      "social.blocks.list",
    intent_name:
      "list_social_blocks",
    description:
      "List profiles blocked by the authenticated Lightek profile.",
    event_type:
      "social.blocks.list.requested"
  },

  {
    name:
      "Social Unblock",
    slug:
      "social.unblock",
    intent_name:
      "unblock_social_profile",
    description:
      "Remove a block previously created by the authenticated Lightek profile.",
    event_type:
      "social.unblock.requested"
  },

  {
    name:
      "Social Friendship Request",
    slug:
      "social.friendship.request",
    intent_name:
      "request_social_friendship",
    description:
      "Request an explicit friendship with another Lightek profile.",
    event_type:
      "social.friendship.request.requested"
  },

  {
    name:
      "Social Friendship Respond",
    slug:
      "social.friendship.respond",
    intent_name:
      "respond_social_friendship",
    description:
      "Accept or decline a friendship request addressed to the authenticated profile.",
    event_type:
      "social.friendship.respond.requested"
  },

  {
    name:
      "Social Friendship End",
    slug:
      "social.friendship.end",
    intent_name:
      "end_social_friendship",
    description:
      "End a friendship involving the authenticated Lightek profile.",
    event_type:
      "social.friendship.end.requested"
  },

  {
    name:
      "Social Block",
    slug:
      "social.block",
    intent_name:
      "block_social_profile",
    description:
      "Create a hard relationship boundary between the authenticated profile and another Lightek profile.",
    event_type:
      "social.block.requested"
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
      "social",

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
      "LightekSocial::Workers::Pwa",

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
        "social"
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
  "Lightek Social capabilities seeded: " \
  "#{capabilities.length}"
)
