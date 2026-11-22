# frozen_string_literal: true

class NevaehCustomerOperationsJob < ApplicationJob
  queue_as :default

  def perform(kind = nil, id = nil)
    case kind
    when "refund"
      ticket = NevaehCustomerService::Cases.scope.find_by(id: id)
      if ticket
        NevaehCustomerService::Refunds.execute!(ticket)
        NevaehCustomerService::Refunds.reconcile!(ticket)
      end
    when "follow_up"
      account = NevaehCustomerService::Outbound.mailbox
      event = Marlon::TicketEvent.find_by(id: id)
      NevaehCustomerService::Outbound.follow_up!(account: account, event: event) if account && event
    when "reminder"
      return unless collections_enabled?

      account = NevaehCustomerService::Outbound.mailbox
      invoice = DymondBank::Invoice.find_by(id: id)
      NevaehCustomerService::Outbound.reminder!(account: account, invoice: invoice) if account && invoice
    when nil
      sweep!
    end
  end

  private

  def sweep!
    cases = NevaehCustomerService::Cases.scope
    cases.where("extra_fields->'customer_service'->'refund'->>'phase' IN (?)", %w[approved submitting pending review_required])
      .find_each { |ticket| self.class.perform_later("refund", ticket.id) }
    return unless NevaehCustomerService::Outbound.mailbox

    Marlon::TicketEvent.where(ticket_id: cases.select(:id), action: NevaehCustomerService::Outbound::UPDATE_ACTIONS)
      .where(created_at: 2.days.ago..Time.current)
      .find_each { |event| self.class.perform_later("follow_up", event.id) }
    return unless collections_enabled?

    today = Date.current
    windows = NevaehCustomerService::Outbound::COLLECTION_WINDOWS
    DymondBank::Invoice.where(billable_type: "User", status: "open", due_date: (today - windows.last.end)..(today - windows.first.begin))
      .where("amount_remaining_cents > 0").find_each { |invoice| self.class.perform_later("reminder", invoice.id) }
  end

  def collections_enabled? = ENV["NEVAEH_COLLECTIONS_ENABLED"] == "1"
end
