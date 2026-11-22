# frozen_string_literal: true

require "digest"

module NevaehCustomerService
  module Cases
    SOURCE = "nevaeh_customer_service"
    CUSTOMER_UPDATE = "Customer update"
    CUSTOMER_REPLY = "Customer reply"
    STAFF_REPLY = "Support reply"
    PUBLIC_EVENTS = [CUSTOMER_UPDATE, CUSTOMER_REPLY, STAFF_REPLY].freeze
    TOPICS = {
      "general" => ["General support", "customer_service", "Customer Service"],
      "find_services" => ["Find my purchased services", "customer_service", "Customer Service"],
      "sign_in_help" => ["Get sign-in and authenticator help", "customer_service", "Customer Service"],
      "refund_request" => ["Request an installation refund", "billing", "Accounting & Billing"],
      "technical" => ["Technical support", "technical", "Technical"],
      "installation_status" => ["Check an installation", "technical", "Technical"],
      "billing" => ["Billing question or dispute", "billing", "Accounting & Billing"],
      "invoice_status" => ["Check an invoice", "billing", "Accounting & Billing"],
      "subscription_status" => ["Check a subscription", "billing", "Accounting & Billing"]
    }.freeze
    GUIDED_HEADINGS = {
      "find_services" => "Find purchased services",
      "sign_in_help" => "Manage sign-in security"
    }.freeze
    INVOICE_STATES = %w[open paid void uncollectible].freeze
    SUBSCRIPTION_STATES = %w[trialing active past_due canceled unpaid incomplete incomplete_expired paused].freeze
    class Invalid < StandardError; end

    module_function

    def scope
      Marlon::Ticket.where("extra_fields->>'source' = ?", SOURCE)
    end

    def customer_case?(ticket)
      ticket.extra_fields.to_h["source"] == SOURCE
    end

    def customer_scope(actor)
      scope.where(submitted_by: actor)
    end

    def invoices(actor)
      actor.invoices.where(status: INVOICE_STATES)
    end

    def subscriptions(actor)
      DymondBank::Subscription.where(subscriber: actor, status: SUBSCRIPTION_STATES)
    end

    def installations(actor)
      LightekCommerce::Installations.scope_for(actor)
    end

    def refundable_installations(actor)
      installations(actor).where(customer_email: actor.email_address, payment_provider: %w[stripe stripe_invoice],
        status: %w[paid fulfilled partially_refunded]).where("total_cents > refunded_cents")
    end

    def open!(actor:, topic:, title:, description:, record_id:)
      raise Invalid, "Sign in to an active account" unless LightekPeople::LifecycleAccess.active?(actor) && actor.persisted?
      label, category, team = TOPICS.fetch(topic) { raise Invalid, "Choose a support topic" }
      reference = case topic
      when "installation_status" then installations(actor).find(record_id)
      when "refund_request" then refundable_installations(actor).find(record_id)
      when "invoice_status" then invoices(actor).find(record_id)
      when "subscription_status" then subscriptions(actor).find(record_id)
      end
      if reference || GUIDED_HEADINGS.key?(topic)
        title = label
        description = topic == "refund_request" ? message!(description) : nil
      else
        title = title.to_s.strip
        description = message!(description)
        raise Invalid, "Enter a subject from 1 to 160 characters" unless title.length.between?(1, 160)
      end

      if topic == "refund_request"
        return reference.with_lock do
          current = customer_scope(actor).where(related: reference, status: %w[open in_progress])
            .where("extra_fields->'customer_service'->>'topic' = ?", topic).first
          current || create_case!(actor, topic, title, description, category, team, reference)
        end
      end

      create_case!(actor, topic, title, description, category, team, reference)
    end

    def create_case!(actor, topic, title, description, category, team, reference)
      Marlon::Ticket.transaction do
        ticket = Marlon::Ticket.create!(
          number: "LT-CS-#{SecureRandom.hex(8).upcase}", title: title, description: description,
          category: category, submitted_by: actor, related: reference,
          assigned_team: team, assigned_rep: "Nevaeh",
          extra_fields: {"source" => SOURCE, "customer_service" => {"topic" => topic, "state" => "queued"}}
        )
        ticket.log!(action: "Ticket submitted", actor: actor)
        ticket
      end
    end

    def reply!(ticket:, actor:, message:)
      message = message!(message)
      ticket.with_lock do
        unless customer_case?(ticket) && ticket.submitted_by_id == actor.id && LightekPeople::LifecycleAccess.active?(actor)
          raise ActiveRecord::RecordNotFound
        end

        fields = ticket.extra_fields
        state = fields.fetch("customer_service")
        unless state.fetch("topic") == "refund_request"
          state.merge!("topic" => handoff_topic(ticket), "state" => "queued")
        end
        ticket.update!(status: "in_progress", resolved_at: nil, extra_fields: fields)
        ticket.log!(action: CUSTOMER_REPLY, detail: message, actor: actor)
      end
      enqueue(ticket)
    end

    def enqueue(ticket)
      return unless NevaehIntelligences::TicketBacklog.enabled?

      NevaehIntelligences::ProcessBacklogJob.perform_later(ticket_id: ticket.id)
    rescue StandardError => error
      Rails.logger.warn("Customer service enqueue failed for ticket #{ticket.id} (#{error.class})")
    end

    def staff_reply!(ticket:, actor:, message:)
      message = message!(message)
      ticket.with_lock do
        raise Invalid, "An authorized support operator is required" unless customer_case?(ticket) &&
          actor.employee? && LightekPeople::LifecycleAccess.active?(actor) && Ability.new(actor).can?(:reply, ticket)

        # A live staff reply fulfills any pending automatic acknowledgment.
        fields = ticket.extra_fields
        state = fields.fetch("customer_service")
        unless state.fetch("topic") == "refund_request"
          state.merge!("topic" => handoff_topic(ticket), "state" => "staff_replied")
        end
        ticket.update!(status: ticket.status == "open" ? "in_progress" : ticket.status, extra_fields: fields)
        ticket.log!(action: STAFF_REPLY, detail: message, actor: actor)
      end
    end

    def process!(ticket)
      ticket.with_lock do
        return unless customer_case?(ticket) && ticket.status != "resolved"

        fields = ticket.extra_fields
        state = fields.fetch("customer_service")
        return unless state["state"] == "queued"

        # Recheck ownership against live records. A saved polymorphic reference
        # alone never authorizes reading financial data.
        actor = ticket.submitted_by
        active = LightekPeople::LifecycleAccess.active?(actor)
        result = verified_answer(ticket, actor, state) if active
        state["state"] = result ? "answered" : "needs_specialist"
        now = Time.current
        ticket.update!(status: result ? "resolved" : "in_progress", resolved_at: result ? now : nil, extra_fields: fields)
        ticket.log!(action: CUSTOMER_UPDATE, detail: result || handoff_message(ticket, state))
        state.fetch("state")
      end
    end

    def verified_answer(ticket, actor, state)
      case state.fetch("topic")
      when "find_services", "sign_in_help"
        guided_answer(state)
      when "installation_status"
        return unless ticket.related_type == "LightekCommerce::Order"
        order = installations(actor).find_by(id: ticket.related_id)
        return unless order

        installation = LightekCommerce::Installations.summary(order)
        state["receipt"] = installation.slice(:id, :payment_status, :state, :ready, :provisioned_at).stringify_keys
        # A known failed setup stays open for Technical to investigate.
        return if installation[:state] == "failed"

        "The saved setup status for #{installation.fetch(:hostname)} is #{installation.fetch(:state).humanize.downcase}. See My Applications for the latest status."
      when "invoice_status"
        return unless ticket.related_type == "DymondBank::Invoice"
        invoice = invoices(actor).find_by(id: ticket.related_id)
        return unless invoice

        state["receipt"] = invoice.attributes.slice("id", "status", "due_date", "paid_at", "updated_at")
        due = if invoice.status == "open" && invoice.due_date
          " Payment is due on #{invoice.due_date.to_fs(:long)}."
        end
        "Dymond Bank shows invoice #{invoice.number.presence || "##{invoice.id}"} as #{invoice.status.humanize.downcase}.#{due} See Billing for its current balance."
      when "subscription_status"
        return unless ticket.related_type == "DymondBank::Subscription"
        subscription = subscriptions(actor).find_by(id: ticket.related_id)
        return unless subscription

        state["receipt"] = subscription.attributes.slice("id", "status", "current_period_end", "updated_at")
        period = if subscription.current_period_end
          " The current billing period ends on #{subscription.current_period_end.to_date.to_fs(:long)}."
        end
        "Dymond Bank shows subscription ##{subscription.id} as #{subscription.status.humanize.downcase}.#{period}"
      end
    end

    def guided_answer(state)
      path = "docs/nevaeh/tutorials/customer_service.md"
      guide = Rails.root.join(path).read
      topic = state.fetch("topic")
      heading = GUIDED_HEADINGS.fetch(topic)
      section = guide.split(/^## /).find { |part| part.lines.first&.strip == heading }
      answer = section&.lines&.drop(1)&.join&.strip
      return if answer.blank?

      state["receipt"] = {"guide" => path, "topic" => topic, "sha256" => Digest::SHA256.hexdigest(guide)}
      answer
    rescue Errno::ENOENT
      nil
    end

    def handoff_topic(ticket)
      {"billing" => "billing", "technical" => "technical"}.fetch(ticket.category, "general")
    end

    def handoff_message(ticket, state)
      if state.fetch("topic") == "installation_status"
        state["receipt"] ? "This installation needs attention. I've sent your case to Technical." :
          "I couldn't verify the installation. I've sent your case to Technical."
      elsif %w[invoice_status subscription_status].include?(state.fetch("topic"))
        "I couldn't verify the requested billing record. I've sent your case to Accounting & Billing for review."
      else
        "I've routed your case to #{ticket.assigned_team}. You can add details and see replies here."
      end
    end

    def message!(value)
      text = value.to_s.strip
      raise Invalid, "Enter a message from 1 to 4,000 characters" unless text.length.between?(1, 4_000)
      text
    end
  end
end
