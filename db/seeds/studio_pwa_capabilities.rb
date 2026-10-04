# frozen_string_literal: true

capabilities = [
  {
    name:
      "Studio PWA Bootstrap",

    slug:
      "studio.pwa.bootstrap",

    intent_name:
      "bootstrap_studio_pwa",

    description:
      "Load the canonical Lightek Studio PWA project, production, scene, and SceneObject workspace.",

    event_type:
      "studio.pwa.bootstrap.requested"
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
      "Studio::Workers::Pwa",

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
        "studio_pwa"
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
  "Studio PWA capabilities seeded: " \
  "#{capabilities.length}"
)
