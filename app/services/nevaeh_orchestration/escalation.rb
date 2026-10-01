# frozen_string_literal: true

module NevaehOrchestration
  class Escalation
    def self.call(plan:, outcome:, decision:, work_item: nil)
      new(
        plan: plan,
        outcome: outcome,
        decision: decision,
        work_item: work_item
      ).call
    end

    def initialize(plan:, outcome:, decision:, work_item: nil)
      @plan = plan
      @outcome = outcome
      @decision = decision
      @work_item = work_item
    end

    def call
      raise "Marlon::Ticket is unavailable" unless defined?(Marlon::Ticket)

      existing = existing_ticket
      return existing if existing

      articles = KnowledgeResolver.for(
        capability: plan.capability,
        additional_article_ids: plan.knowledge_article_ids
      )

      ticket = Marlon::Ticket.create!(
        category: "technical",
        title: "Nevaeh escalation — #{plan.capability.humanize}",
        description: description,
        priority: "high",
        urgency: 8,
        status: "open",
        organization_name: "Lightek MCG",
        assigned_team: "Technical",
        assigned_rep: "Nevaeh",
        related: ticket_subject,
        extra_fields: {
          "source" => "nevaeh",
          "correlation_id" => plan.correlation_id,
          "capability" => plan.capability,
          "work_item_id" => work_item&.id,
          "handler" => plan.handler,
          "decision" => decision.to_h.deep_stringify_keys,
          "outcome" => outcome.to_h.deep_stringify_keys,
          "kb_articles_consulted" => articles.map { |article| article_identifier(article) }
        }.compact
      )

      log_ticket!(
        ticket,
        action: "nevaeh_escalated",
        detail: decision.reason
      )

      if articles.any?
        log_ticket!(
          ticket,
          action: "kb_consulted",
          detail: "Knowledge consulted: #{articles.map { |a| article_identifier(a) }.join(', ')}"
        )
      end

      ticket
    end

    private

    attr_reader :plan, :outcome, :decision, :work_item

    def ticket_subject
      work_item || plan.subject
    end

    def existing_ticket
      subject = ticket_subject
      return nil unless subject

      Marlon::Ticket.find_by(
        related_type: subject.class.base_class.name,
        related_id: subject.id
      )
    end

    def description
      <<~TEXT
        Nevaeh exhausted the currently known automated path.

        Correlation: #{plan.correlation_id}
        Capability: #{plan.capability}
        Handler: #{plan.handler}
        WorkItem: #{work_item&.id || outcome.work_item_id || "N/A"}

        Decision: #{decision.reason}

        Error: #{outcome.error_class || "N/A"}: #{outcome.error_message || "N/A"}

        The request has been escalated because retry, alternate execution,
        or expected-result validation could not resolve the intent automatically.
      TEXT
    end

    def log_ticket!(ticket, action:, detail:)
      if ticket.respond_to?(:log!)
        ticket.log!(
          action: action,
          detail: detail
        )
      elsif defined?(Marlon::TicketEvent)
        Marlon::TicketEvent.create!(
          ticket: ticket,
          action: action,
          detail: detail
        )
      end
    rescue StandardError => error
      Rails.logger.warn(
        "[Nevaeh::Escalation] ticket event failed: " \
        "#{error.class}: #{error.message}"
      )
    end

    def article_identifier(article)
      if article.respond_to?(:article_id) && article.article_id.present?
        article.article_id
      else
        article.id
      end
    end
  end
end
