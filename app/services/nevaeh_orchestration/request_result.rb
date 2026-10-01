# frozen_string_literal: true

module NevaehOrchestration
  class RequestResult
    attr_reader \
      :event,
      :intent,
      :capability,
      :knowledge_articles,
      :plan,
      :authorization,
      :work_item

    def initialize(
      event:,
      intent:,
      capability:,
      knowledge_articles:,
      plan:,
      authorization:,
      work_item:
    )
      @event = event
      @intent = intent
      @capability = capability
      @knowledge_articles = Array(knowledge_articles)
      @plan = plan
      @authorization = authorization
      @work_item = work_item
    end

    def correlation_id
      event.correlation_id
    end

    def work_item_id
      work_item&.id
    end

    def authorized?
      authorization&.allowed? == true
    end

    def dispatched?
      work_item.present?
    end

    def knowledge_article_ids
      knowledge_articles.map do |article|
        if article.respond_to?(:article_id) &&
           article.article_id.present?
          article.article_id
        else
          article.id
        end
      end
    end

    def to_h
      {
        correlation_id: correlation_id,
        event: event.to_h,
        intent: intent.to_h,
        capability: {
          id: capability.id,
          slug: capability.slug,
          name: capability.name,
          domain: capability.domain
        },
        knowledge_article_ids: knowledge_article_ids,
        plan: plan.to_h,
        authorization: authorization.to_h,
        work_item: work_item && {
          id: work_item.id,
          kind: work_item.kind,
          handler: work_item.handler,
          queue: work_item.queue,
          status: work_item.status,
          correlation_id: work_item.correlation_id
        }
      }
    end
  end
end
