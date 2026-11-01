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

    def sync_github
      authorize! :execute_nevaeh, Marlon::Ticket
      capability = NevaehIntelligences::StructuredTicket.registered!
      capability.with_lock do
        metadata = capability.metadata.to_h.deep_stringify_keys
        metadata["github_engineering"] = {"sync_enabled" => true, "actor_id" => current_user.id}
        capability.update!(metadata: metadata)
      end
      NevaehIntelligences::SyncGithubIssuesJob.perform_later
      redirect_to employee_nevaeh_overview_path, notice: "GitHub intake queued. Requests without a learned procedure go to Technical Support / Admin queue."
    end

    private

    def authorize_overview!
      authorize! :read, Marlon::Ticket
    end
  end
end
