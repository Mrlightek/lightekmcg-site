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
      head :forbidden unless NevaehIntelligences::TicketDraftAccessV7a.allowed?
    end
  end
end
