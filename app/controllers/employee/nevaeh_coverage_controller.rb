# frozen_string_literal: true
module Employee
  class NevaehCoverageController < Employee::ApplicationController
    before_action :authorize_coverage!
    before_action :local_only!
    def index
      @destination = params[:destination].to_s
      @report = if @destination.present?
        NevaehIntelligences::AcceptanceCoverageV7a.inspect_bundle(destination: @destination)
      end
      respond_to do |format|
        format.html
        format.json { render json: { report: @report, read_only: true } }
      end
    rescue NevaehIntelligences::AcceptanceCoverageV7a::Rejected => e
      render plain: "Coverage audit refused: #{e.message}", status: :unprocessable_entity
    end
    private
    def authorize_coverage!
      authorize! :manage, Marlon::Ticket
    end
    def local_only!
      # V8_6A_READ_GATE: authenticated super admins may inspect; local opt-in still gates other users.
      head :forbidden unless (action_name == "index" && current_user&.role == "super_admin") || NevaehIntelligences::TicketDraftAccessV7a.allowed?
    end
  end
end
