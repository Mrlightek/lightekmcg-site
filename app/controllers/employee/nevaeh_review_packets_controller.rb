# frozen_string_literal: true
module Employee
  class NevaehReviewPacketsController < Employee::ApplicationController
    before_action :authorize_review!
    before_action :local_only!
    def index
      @destination = params[:destination].to_s
      @packet = if @destination.present?
        NevaehIntelligences::AcceptanceReviewPacketV7a.build(destination: @destination)
      end
      respond_to do |format|
        format.html
        format.json { render json: { packet: @packet, read_only: true } }
      end
    rescue NevaehIntelligences::AcceptanceReviewPacketV7a::Rejected => e
      render plain: "Review packet refused: #{e.message}", status: :unprocessable_entity
    end
    private
    def authorize_review!
      authorize! :manage, Marlon::Ticket
    end
    def local_only!
      head :forbidden unless NevaehIntelligences::TicketDraftAccessV7a.allowed?
    end
  end
end
