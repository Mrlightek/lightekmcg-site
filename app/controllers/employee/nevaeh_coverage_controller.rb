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
      head :forbidden unless NevaehIntelligences::TicketDraftAccessV7a.allowed?
    end
  end
end
