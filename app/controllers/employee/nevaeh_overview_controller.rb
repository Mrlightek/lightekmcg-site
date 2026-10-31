# frozen_string_literal: true
module Employee
  class NevaehOverviewController < Employee::ApplicationController
    before_action :authorize_overview!

    def index
      @capabilities = NevaehIntelligences::CapabilityConsoleV7a.list
      @services = NevaehIntelligences::CapabilityConsoleV7a.services
      @registered_services = @services.size
      @present_services = @services.count { |row| row.fetch('state') == 'present' }
      @executable_services = @services.count { |row| row.fetch('executable') == true }
      @ticket_counts = Marlon::Ticket.group(:status).count
      @backlog_counts = Marlon::Ticket.group(Arel.sql("COALESCE(extra_fields->'nevaeh_backlog'->>'status', 'not_analyzed')")).count
      @backlog_tickets = Marlon::Ticket.where.not(status: "resolved").order(:id).limit(100)
      respond_to do |format|
        format.html
        format.json do
          render json: {
            read_only: true,
            ticket_counts: @ticket_counts,
            backlog_counts: @backlog_counts,
            tickets: @backlog_tickets.map { |ticket| {id: ticket.id, number: ticket.number,
              status: ticket.status, backlog: ticket.extra_fields.to_h.fetch("nevaeh_backlog", {}),
              execution: ticket.extra_fields.to_h.fetch("nevaeh", {})} },
            capabilities: @capabilities,
            services: @services,
            summary: { capability_count: @capabilities.size, registered_services: @registered_services,
              present_services: @present_services, executable_services: @executable_services }
          }
        end
      end
    end

    private

    def authorize_overview!
      authorize! :read, Marlon::Ticket
    end
  end
end
