# frozen_string_literal: true

require "digest"

self_model_path =
  Rails.root.join(
    "config",
    "nevaeh",
    "self_model.json"
  )

history_path =
  Rails.root.join(
    "config",
    "nevaeh",
    "development_history.json"
  )

history_doc_path =
  Rails.root.join(
    "docs",
    "nevaeh",
    "development_history.md"
  )

self_model =
  JSON.parse(
    self_model_path.read
  )

history =
  JSON.parse(
    history_path.read
  )

capability =
  NevaehCapability
    .find_or_initialize_by(
      slug:
        "nevaeh.self.inspect"
    )

capability.assign_attributes(
  name:
    "Nevaeh Self Knowledge",

  domain:
    "nevaeh",

  description:
    "Inspect Nevaeh's own architecture, learning model, observability contract, and development lineage.",

  intent_name:
    "inspect_nevaeh_self",

  subject_type:
    nil,

  handler:
    "NevaehOrchestration::Workers::SelfKnowledge",

  queue:
    "default",

  priority:
    5,

  gatekeeper_capability:
    "nevaeh.self.inspect",

  intent_patterns: [
    "how do you work",
    "how do you learn",
    "where did you come from",
    "show your development history",
    "show your observability model"
  ],

  expected_outcome: {
    "kind" =>
      "nevaeh_self_knowledge"
  },

  failure_policy: {
    "retries" =>
      1,

    "escalate" =>
      true
  },

  realtime:
    {},

  input_adapter:
    {},

  metadata: {
    "self_model_version" =>
      self_model.fetch(
        "self_model_version"
      ),

    "history_snapshot_id" =>
      history.fetch(
        "snapshot_id"
      ),

    "history_source_head" =>
      history.fetch(
        "source_head"
      )
  },

  knowledge_article_ids: [
    "nevaeh-origin-learning-model",
    "nevaeh-development-history"
  ],

  event_types: [
    "nevaeh.self.inspect.requested"
  ],

  enabled:
    true
)

capability.save!

if defined?(
     DymondKb::Topic
   ) &&
   defined?(
     DymondKb::Article
   ) &&
   DymondKb::Topic.table_exists? &&
   DymondKb::Article.table_exists?

  topic =
    DymondKb::Topic
      .find_or_initialize_by(
        topic_id:
          "nevaeh-self"
      )

  topic.assign_attributes(
    name:
      "Nevaeh Self Knowledge",

    icon:
      "sparkles",

    description:
      "Nevaeh's durable origin, architecture, learning model, observability contract, and development lineage.",

    sort_order:
      5
  )

  topic.save!

  origin_body =
    <<~BODY
      # Nevaeh — Origin, Architecture, and Learning Model

      #{self_model.dig("identity", "purpose")}

      ## Product laws

      #{self_model.fetch("product_laws").map { |law| "- #{law}" }.join("\n")}

      ## Learning loop

      #{self_model.dig("learning_loop", "steps").map.with_index(1) { |step, index| "#{index}. #{step}" }.join("\n")}

      ## Learning principle

      #{self_model.dig("learning_loop", "learning_principle")}

      ## Observability law

      #{self_model.dig("observability_contract", "law")}

      Full machine-readable self model:
      `config/nevaeh/self_model.json`
    BODY

  origin_article =
    DymondKb::Article
      .find_or_initialize_by(
        article_id:
          "nevaeh-origin-learning-model"
      )

  origin_article.assign_attributes(
    topic_id:
      topic.id,

    title:
      "Nevaeh — Origin, Architecture, and Learning Model",

    article_type:
      "reference",

    excerpt:
      "Nevaeh's durable self-model: purpose, orchestration architecture, learning loop, and observability law.",

    body:
      origin_body,

    read_minutes:
      6,

    featured:
      true,

    sort_order:
      1,

    metadata: {
      "nevaeh_capability" =>
        "nevaeh.self.inspect",

      "gatekeeper_capability" =>
        "nevaeh.self.inspect",

      "capability" =>
        "nevaeh.self.inspect",

      "kind" =>
        "self_model",

      "self_model_version" =>
        self_model.fetch(
          "self_model_version"
        ),

      "source_path" =>
        "config/nevaeh/self_model.json",

      "source_sha256" =>
        Digest::SHA256.hexdigest(
          self_model_path.read
        )
    }
  )

  origin_article.save!

  history_article =
    DymondKb::Article
      .find_or_initialize_by(
        article_id:
          "nevaeh-development-history"
      )

  history_article.assign_attributes(
    topic_id:
      topic.id,

    title:
      "Nevaeh — Development History",

    article_type:
      "reference",

    excerpt:
      "Provenance-backed lineage of Nevaeh's code ancestry, project milestones, capability registry, and learning architecture.",

    body:
      history_doc_path.read,

    read_minutes:
      10,

    featured:
      true,

    sort_order:
      2,

    metadata: {
      "nevaeh_capability" =>
        "nevaeh.self.inspect",

      "gatekeeper_capability" =>
        "nevaeh.self.inspect",

      "capability" =>
        "nevaeh.self.inspect",

      "kind" =>
        "development_history",

      "history_snapshot_id" =>
        history.fetch(
          "snapshot_id"
        ),

      "source_head" =>
        history.fetch(
          "source_head"
        ),

      "source_path" =>
        "config/nevaeh/development_history.json",

      "source_sha256" =>
        Digest::SHA256.hexdigest(
          history_path.read
        )
    }
  )

  history_article.save!

  puts(
    "Nevaeh self-knowledge KB articles seeded: 2"
  )
else
  puts(
    "Nevaeh self-knowledge KB seed skipped: DymondKb tables unavailable"
  )
end

puts(
  "Nevaeh self-knowledge capability seeded: " \
  "#{capability.slug}"
)
