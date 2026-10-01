# frozen_string_literal: true

class NevaehCapability < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :domain, presence: true
  validates :intent_name, presence: true
  validates :handler, presence: true
  validates :queue, presence: true

  validates :priority,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 10
            }

  scope :enabled, -> { where(enabled: true) }
  scope :for_domain, ->(domain) { where(domain: domain.to_s) }

  before_validation :normalize_slug

  def build_intent(
    instruction: nil,
    parameters: {},
    correlation_id: nil,
    metadata: {}
  )
    NevaehOrchestration::Intent.new(
      name: intent_name,
      instruction: instruction,
      parameters: parameters,
      capability_hint: slug,
      correlation_id: correlation_id,
      metadata: metadata
    )
  end

  def build_plan(
    subject: nil,
    args: [],
    instruction: nil,
    parameters: {},
    context: {},
    correlation_id: nil,
    resolved_knowledge_article_ids: nil
  )
    intent = build_intent(
      instruction: instruction,
      parameters: parameters,
      correlation_id: correlation_id
    )

    NevaehOrchestration::Plan.new(
      intent: intent,
      capability: slug,
      handler: handler,
      subject: subject,
      args: args,
      queue: queue,
      priority: priority,
      expected_outcome: expected_outcome,
      failure_policy: failure_policy,
      realtime: realtime,
      knowledge_article_ids:
        resolved_knowledge_article_ids || knowledge_article_ids,
      context: context,
      correlation_id: intent.correlation_id
    )
  end

  private

  def normalize_slug
    self.slug = slug.to_s.strip.downcase
  end
end
