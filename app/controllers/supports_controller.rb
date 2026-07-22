# frozen_string_literal: true
# The real public ticket hub — replaces the generic Rails scaffold. Talks
# directly to Marlon::Ticket; the old Support model is left untouched/unused.
class SupportsController < ApplicationController
  layout false  # full standalone page (own <html>/<head>), same as store/catalog.

  PRIORITY_ABBR = { "low" => "LOW", "medium" => "MED", "high" => "HIGH", "critical" => "CRIT" }.freeze
  STATUS_MAP    = { "open" => "open", "in_progress" => "progress", "resolved" => "resolved" }.freeze

  def index
    @categories = Marlon::TicketCategories::ALL
    tickets     = Marlon::Ticket.where(submitted_by: current_user).open_first.limit(20)
    @my_tickets_json = tickets.map { |t| ticket_to_hub_json(t) }
  end

  def create
    ticket = Marlon::Ticket.new(ticket_params)
    ticket.submitted_by = current_user
    ticket.organization_name ||= current_user&.full_name

    if ticket.save
      ticket.log!(action: "Ticket submitted", actor: current_user)
      render json: { ok: true, number: ticket.number, id: ticket.id }
    else
      render json: { ok: false, error: ticket.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def reply
    ticket = Marlon::Ticket.find(params[:id])
    ticket.log!(action: "#{current_user.full_name} replied", detail: params[:detail], actor: current_user)
    render json: { ok: true }
  end

  private

  def ticket_params
    params.require(:ticket).permit(:category, :title, :description, :priority, :urgency,
                                    :organization_name, :reseller_id).tap do |p|
      p[:extra_fields] = { "notes" => params.dig(:ticket, :extra_notes) }.compact if params.dig(:ticket, :extra_notes).present?
    end
  end

  def ticket_to_hub_json(ticket)
    meta = ticket.category_meta || {}
    {
      id: ticket.id,
      num: ticket.number,
      cat: ticket.category,
      subject: ticket.title,
      status: STATUS_MAP[ticket.status] || ticket.status,
      time: relative_time(ticket.created_at),
      priority: PRIORITY_ABBR[ticket.priority] || ticket.priority.upcase,
      events: ticket.events.order(:created_at).map { |e| event_to_hub_json(e, meta[:color]) }
    }
  end

  def event_to_hub_json(event, category_color)
    action = event.action.to_s.downcase
    dot = if action.include?("resolved") || action.include?("assigned")
            "#18C870"
          else
            category_color || "#00B4CC"
          end
    { time: event.created_at.strftime("%l:%M %p").strip, dot: dot, action: event.action, detail: event.detail.to_s }
  end

  def relative_time(t)
    diff = Time.current - t
    if diff < 1.hour   then "#{[(diff / 60).round, 1].max}m ago"
    elsif diff < 1.day then "#{(diff / 3600).round}h ago"
    else "#{(diff / 86400).round}d ago"
    end
  end
end
