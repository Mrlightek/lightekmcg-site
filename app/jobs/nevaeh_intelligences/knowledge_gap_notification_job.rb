# frozen_string_literal: true
module NevaehIntelligences
  class KnowledgeGapNotificationJob < ApplicationJob
    queue_as :default
    class Unavailable < StandardError; end
    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    def perform(ticket_id)
      ticket = Marlon::Ticket.find_by(id: ticket_id)
      return unless ticket && ticket.status != "resolved"
      if CentralReporting.client?
        CentralReporting.deliver!(ticket: ticket)
        return
      end
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        gap = fields["nevaeh_knowledge_gap"]
        return unless gap && gap.dig("notification", "state") != "submitted"
        administrators = User.where(role: %w[super_admin admin]).order(:id).to_a
        raise Unavailable, "No administrator is configured for the technical escalation queue" if administrators.empty?
        sender = LightekMail::Account.where(user_id: administrators.map(&:id)).order(:id).detect(&:sending_ready?)
        raise Unavailable, "No sending-ready administrator mailbox is configured for escalation notifications" unless sender
        notification = gap.fetch("notification")
        # Snapshot content and recipient IDs before submission. The existing
        # mail outbox's idempotency key prevents duplicate mail after a crash.
        unless notification["recipient_ids"]
          notification.merge!("recipient_ids" => administrators.map(&:id), "subject" => "Nevaeh needs a lesson: #{ticket.number}",
            "text" => "Ticket #{ticket.number}: #{ticket.title}\n\n#{gap.fetch('reason')}\n\nAssigned to Technical Team / Admin queue. Review this request in Dymond Dash Support Tickets (ticket ID #{ticket.id}). Teach a procedure and verify its acceptance checks before resuming the request.")
          ticket.update!(extra_fields: fields)
        end
        messages = notification.fetch("recipient_ids").map do |id|
          admin = administrators.find { |record| record.id == id }
          next unless admin # Revoked administrators receive no new notifications.
          LightekMail::Submission.create!(account: sender,
            attributes: {to: admin.email_address, subject: notification.fetch("subject"), text: notification.fetch("text")},
            idempotency_key: "nevaeh_gap_#{ticket.id}_#{id}").id
        end.compact
        notification.merge!("state" => "submitted", "message_ids" => messages, "submitted_at" => Time.current.iso8601)
        ticket.update!(extra_fields: fields)
        ticket.log!(action: "nevaeh_knowledge_gap_notification_submitted", detail: {"message_ids" => messages}.to_json)
      end
    rescue StandardError => error
      if ticket
        ticket.with_lock do
          fields = ticket.extra_fields.to_h.deep_stringify_keys
          fields.dig("nevaeh_knowledge_gap", "notification")&.merge!("state" => "pending", "blocker" => error.message.to_s.first(500))
          ticket.update!(extra_fields: fields)
        end
      end
      raise
    end
  end
end
