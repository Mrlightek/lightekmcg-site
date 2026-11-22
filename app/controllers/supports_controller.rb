# frozen_string_literal: true
# The real public ticket hub — replaces the generic Rails scaffold. Talks
# directly to Marlon::Ticket; the old Support model is left untouched/unused.
class SupportsController < ApplicationController
  layout false  # full standalone page (own <html>/<head>), same as store/catalog.

  PRIORITY_ABBR = { "low" => "LOW", "medium" => "MED", "high" => "HIGH", "critical" => "CRIT" }.freeze
  STATUS_MAP    = { "open" => "open", "in_progress" => "progress", "resolved" => "resolved" }.freeze
  NEVAEH_UPDATES = {
    "nevaeh_backlog_ready" => "Nevaeh has reviewed your report and identified a support procedure.",
    "nevaeh_backlog_escalated" => "Nevaeh has reviewed your report. Your ticket is open for technical follow-up.",
    "nevaeh_project_health_verified" => "Nevaeh verified that the service is healthy and closed the incident."
  }.freeze

  def index
    return head :unauthorized unless current_user

    @categories = Marlon::TicketCategories::ALL
    tickets     = Marlon::Ticket.where(submitted_by: current_user).open_first.limit(20)
    @my_tickets_json = tickets.map { |t| ticket_to_hub_json(t) }
  end

  def create
    return head :unauthorized unless current_user

    ticket = Marlon::Ticket.new(ticket_params)
    ticket.submitted_by = current_user
    ticket.organization_name ||= current_user&.full_name

    if ticket.save
      ticket.log!(action: "Ticket submitted", actor: current_user)
      render json: { ok: true, number: ticket.number, id: ticket.id, ticket: ticket_to_hub_json(ticket) }
    else
      render json: { ok: false, error: ticket.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def reply
    return head :unauthorized unless current_user

    ticket = Marlon::Ticket.find_by(id: params[:id], submitted_by: current_user)
    return render json: { ok: false, error: "Ticket was not found." }, status: :not_found unless ticket

    detail = params[:detail]
    unless detail.is_a?(String) && detail.strip.length.between?(1, 8_000)
      return render json: { ok: false, error: "Enter a reply between 1 and 8,000 characters." }, status: :unprocessable_entity
    end

    ticket.with_lock do
      if ticket.status == "resolved"
        return render json: { ok: false, error: "This ticket is closed." }, status: :conflict
      end

      ticket.log!(action: "#{current_user.full_name} replied", detail: detail.strip, actor: current_user)
    end
    ticket.enqueue_nevaeh_backlog if ticket.category.in?(%w[technical deployment])
    render json: { ok: true, ticket: ticket_to_hub_json(ticket) }
  end

  private

  def ticket_params
    params.require(:ticket).permit(:category, :title, :description, :priority, :urgency,
                                    :organization_name, :reseller_id).tap do |p|
      p[:extra_fields] = { "source" => "support_hub", "notes" => params.dig(:ticket, :extra_notes) }.compact
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
      events: customer_timeline(ticket, meta[:color])
    }
  end

  def customer_timeline(ticket, category_color)
    events = ticket.events.order(:created_at, :id).to_a
    latest_update = events.reverse_each.find { |event| NEVAEH_UPDATES.key?(event.action) }
    events.filter_map do |event|
      case
      when event == latest_update
        timeline_entry(event, category_color, "Nevaeh support update", NEVAEH_UPDATES.fetch(event.action))
      when event.action == "Ticket submitted"
        timeline_entry(event, category_color, event.action, ticket.description.to_s)
      when event.action == "Ticket resolved"
        timeline_entry(event, category_color, event.action, "")
      when event.actor_id && event.action.end_with?(" replied")
        timeline_entry(event, category_color, event.action, event.detail.to_s)
      end
    end
  end

  def timeline_entry(event, category_color, action, detail)
    { time: event.created_at.strftime("%l:%M %p").strip, dot: category_color || "#00B4CC", action: action, detail: detail }
  end

  def relative_time(t)
    diff = Time.current - t
    if diff < 1.hour   then "#{[(diff / 60).round, 1].max}m ago"
    elsif diff < 1.day then "#{(diff / 3600).round}h ago"
    else "#{(diff / 86400).round}d ago"
    end
  end
end
