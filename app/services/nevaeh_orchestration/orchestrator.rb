# frozen_string_literal: true

module NevaehOrchestration
  class Orchestrator
    def self.call(
      event_type:,
      source:,
      subject: nil,
      actor: nil,
      context: {},
      payload: {},
      capability_hint: nil,
      args: [],
      instruction: nil,
      parameters: {},
      correlation_id: nil
    )
      new(
        event_type: event_type,
        source: source,
        subject: subject,
        actor: actor,
        context: context,
        payload: payload,
        capability_hint: capability_hint,
        args: args,
        instruction: instruction,
        parameters: parameters,
        correlation_id: correlation_id
      ).call
    end

    def initialize(**attributes)
      @attributes = attributes
    end

    def call
      event = build_event

      intent =
        IntentResolver.call(
          event: event,
          capability_hint: attributes[:capability_hint],
          instruction: attributes[:instruction],
          parameters: attributes[:parameters]
        )

      capability =
        CapabilityRegistry.resolve(
          intent: intent
        )

      knowledge =
        KnowledgeResolver.for(
          capability: capability.slug,
          additional_article_ids:
            capability.knowledge_article_ids
        )

      knowledge_ids =
        knowledge.map do |article|
          if article.respond_to?(:article_id) &&
             article.article_id.present?
            article.article_id
          else
            article.id
          end
        end

      plan =
        capability.build_plan(
          subject: attributes[:subject],
          args: attributes[:args],
          instruction: intent.instruction,
          parameters: intent.parameters,
          context:
            attributes[:context].to_h.merge(
              "event_type" => event.event_type,
              "source" => event.source
            ),
          correlation_id: event.correlation_id,
          resolved_knowledge_article_ids: knowledge_ids
        )

      authorization =
        Gatekeeper.authorize_capability!(
          capability:
            capability.gatekeeper_capability.presence ||
            capability.slug,
          subject: attributes[:subject],
          context: {
            correlation_id: event.correlation_id,
            event_type: event.event_type,
            source: event.source,
            actor: event.actor_ref,
            knowledge_article_ids: knowledge_ids
          }.compact
        )

      work_item =
        DispatchService.call(
          plan: plan
        )

      RequestResult.new(
        event: event,
        intent: intent,
        capability: capability,
        knowledge_articles: knowledge,
        plan: plan,
        authorization: authorization,
        work_item: work_item
      )
    end

    private

    attr_reader :attributes

    def build_event
      Event.new(
        event_type: attributes.fetch(:event_type),
        source: attributes.fetch(:source),
        subject: attributes[:subject],
        actor: attributes[:actor],
        context: attributes[:context],
        payload: attributes[:payload],
        correlation_id: attributes[:correlation_id]
      )
    end
  end
end
