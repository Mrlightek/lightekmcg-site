# frozen_string_literal: true
LightekCommunity::Workers::Pwa::ACTIONS.each do |action|
  slug = "community.#{action.delete_prefix('community_').tr('_', '.')}"
  record = NevaehCapability.find_or_initialize_by(slug: slug)
  record.assign_attributes(name: slug.humanize, domain: "community", intent_name: action,
    description: "Perform #{action.humanize.downcase} as the authenticated Lightek member within the current site.",
    handler: "LightekCommunity::Workers::Pwa", queue: "default", priority: 5,
    gatekeeper_capability: slug, event_types: ["#{slug}.requested"], enabled: true,
    intent_patterns: [], expected_outcome: {}, failure_policy: { "retries" => 1, "escalate" => true },
    realtime: {}, input_adapter: {}, metadata: { "surface" => "communities" }, knowledge_article_ids: [])
  record.save!
end
