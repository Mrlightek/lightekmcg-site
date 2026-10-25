# frozen_string_literal: true
module Employee
  class NevaehAcceptanceEvidenceController < Employee::ApplicationController
    before_action :authorize_evidence!
    before_action :local_only!
    def index
      @destination = params[:destination].to_s
      @report = if @destination.present?
        NevaehIntelligences::AcceptanceEvidenceV7a.inspect_bundle(destination: @destination)
      end
      respond_to do |format|
        format.html
        format.json { render json: { report: @report, read_only: true } }
      end
    rescue NevaehIntelligences::AcceptanceEvidenceV7a::Rejected => e
      render plain: "Evidence audit refused: #{e.message}", status: :unprocessable_entity
    end
    private
    def authorize_evidence!
      authorize! :manage, Marlon::Ticket
    end
    def local_only!
      # V8_6A_READ_GATE: authenticated super admins may inspect; local opt-in still gates other users.
      head :forbidden unless (action_name == "index" && current_user&.role == "super_admin") || NevaehIntelligences::TicketDraftAccessV7a.allowed?
    end
  end
end
