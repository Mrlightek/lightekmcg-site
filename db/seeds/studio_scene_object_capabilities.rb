# frozen_string_literal: true

definitions = [
  {
    name:
      "Studio SceneObject Create",

    slug:
      "studio.scene_object.create",

    intent_name:
      "create_studio_scene_object",

    description:
      "Create a SceneObject inside a Lightek Studio scene.",

    event_type:
      "studio.scene_object.create.requested"
  },

  {
    name:
      "Studio SceneObject Transform",

    slug:
      "studio.scene_object.transform",

    intent_name:
      "transform_studio_scene_object",

    description:
      "Update SceneObject name, placement and transform data.",

    event_type:
      "studio.scene_object.transform.requested"
  },

  {
    name:
      "Studio SceneObject Duplicate",

    slug:
      "studio.scene_object.duplicate",

    intent_name:
      "duplicate_studio_scene_object",

    description:
      "Duplicate an existing SceneObject inside a Studio scene.",

    event_type:
      "studio.scene_object.duplicate.requested"
  },

  {
    name:
      "Studio SceneObject Destroy",

    slug:
      "studio.scene_object.destroy",

    intent_name:
      "destroy_studio_scene_object",

    description:
      "Remove a SceneObject from a Lightek Studio scene.",

    event_type:
      "studio.scene_object.destroy.requested"
  }
].freeze

definitions.each do |definition|
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
      "studio",

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
      "Studio::Workers::SceneObjectMutation",

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
        "studio_pwa",

      "resource" =>
        "scene_object"
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
  "Studio SceneObject capabilities seeded: " \
  "#{definitions.length}"
)
