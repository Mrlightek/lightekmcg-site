# frozen_string_literal: true

module NevaehCustomerService
  module Outbound
    UPDATE_ACTIONS = [Cases::CUSTOMER_UPDATE, Cases::STAFF_REPLY].freeze
    COLLECTION_WINDOWS = [3..9, 10..16].freeze

    module_function

    def mailbox
      account = LightekMail::Account.mailboxes.find_by(id: ENV.fetch("NEVAEH_SUPPORT_MAILBOX_ID", nil))
      return unless account&.sending_ready? && LightekPeople::LifecycleAccess.active?(account.user)

      LightekMail::Access.accounts(account.user).find_by(id: account.id)
    end

    def follow_up!(account:, event:)
      ticket = event.ticket
      ticket.with_lock do
        return unless Cases.customer_case?(ticket) && UPDATE_ACTIONS.include?(event.action)
        return unless ticket.events.where(action: Cases::PUBLIC_EVENTS).maximum(:id) == event.id

        submit!(account, ticket.submitted_by, "Lightek support case update",
          "Your support case has an update. Sign in to Customer Service & Billing to view it.\n\n" \
          "https://lightekmcg.com/dashboard/customer-service/cases/#{ticket.id}",
          "support_event_#{event.id}")
      end
    end

    def reminder!(account:, invoice:, today: Date.current)
      invoice.with_lock do
        window = reminder_window(invoice, today)
        return unless window

        customer = invoice.billable

        submit!(account, customer, "Lightek billing reminder",
          "Your account has an overdue invoice. Sign in to Customer Service & Billing to view the current balance or open a billing case.\n\n" \
          "https://lightekmcg.com/dashboard/customer-service#billing",
          "billing_reminder_#{invoice.id}_#{invoice.due_date.strftime('%Y%m%d')}_#{window.begin}")
      end
    end

    def reminder_window(invoice, today)
      return unless invoice && invoice.billable_type == "User" && invoice.status == "open" &&
        invoice.amount_remaining_cents.positive? && invoice.due_date

      window = COLLECTION_WINDOWS.find { |candidate| candidate.cover?((today - invoice.due_date).to_i) }
      return unless window

      customer = invoice.billable
      return unless LightekPeople::LifecycleAccess.active?(customer)
      return if Cases.customer_scope(customer).where(category: "billing", status: %w[open in_progress]).exists?

      window
    end

    # The mail job checks again after scanning, just before it hands off to SMTP.
    def current?(message)
      key = message.idempotency_key.to_s
      if (parts = key.match(/\Asupport_event_([0-9]+)\z/))
        event = Marlon::TicketEvent.find_by(id: parts[1])
        ticket = event&.ticket
        return false unless ticket && Cases.customer_case?(ticket) && UPDATE_ACTIONS.include?(event.action) &&
          ticket.events.where(action: Cases::PUBLIC_EVENTS).maximum(:id) == event.id
        customer = ticket.submitted_by
      elsif (parts = key.match(/\Abilling_reminder_([0-9]+)_([0-9]{8})_([0-9]+)\z/))
        return false unless ENV["NEVAEH_COLLECTIONS_ENABLED"] == "1"

        invoice = DymondBank::Invoice.find_by(id: parts[1])
        window = reminder_window(invoice, Date.current)
        return false unless window && window.begin == parts[3].to_i && invoice.due_date.strftime("%Y%m%d") == parts[2]
        customer = invoice.billable
      else
        return true
      end

      ENV["NEVAEH_SUPPORT_MAILBOX_ID"].to_s == message.account_id.to_s &&
        LightekPeople::LifecycleAccess.active?(customer) && message.to_addresses == [customer.email_address.to_s.downcase]
    end

    def submit!(account, customer, subject, body, key)
      return unless LightekPeople::LifecycleAccess.active?(customer) && customer.email_address.present?

      existing = account.messages.find_by(idempotency_key: key)
      if existing
        LightekMail::DeliverJob.perform_later(existing.id) if existing.state == "queued" && existing.updated_at < 15.minutes.ago
        return existing
      end

      LightekMail::Submission.create!(account: account, idempotency_key: key,
        attributes: {"to" => customer.email_address, "subject" => subject, "text" => body})
    end
  end
end
