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
      respond_to do |format|
        format.html
        format.json do
          render json: {
            read_only: true,
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
