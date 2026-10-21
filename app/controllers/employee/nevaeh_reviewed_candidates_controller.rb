# frozen_string_literal: true
module Employee
  class NevaehReviewedCandidatesController < Employee::ApplicationController
    before_action :authorize_review!
    before_action :local_only!
    def index
      @ticket_id = params[:ticket_id].to_s
      @key = params[:key].to_s
      @capabilities = NevaehIntelligences::YamlCapabilityRegistryV7a.list(root: Rails.root.to_s)
      @preview = if @ticket_id.present? && @key.present?
        NevaehIntelligences::ReviewedCandidatePipelineV7a.preview(ticket: Marlon::Ticket.find(Integer(@ticket_id, 10)), key: @key)
      end
      respond_to do |format|
        format.html
        format.json { render json: { preview: @preview, production_allowed: false } }
      end
    rescue StandardError => e
      raise if e.is_a?(CanCan::AccessDenied)
      raise unless allowed_error?(e)
      render plain: "Reviewed preview refused: #{e.message}", status: :unprocessable_entity
    end
    def create
      ticket = Marlon::Ticket.find(Integer(params.require(:ticket_id), 10))
      key = params.require(:key).to_s
      require "tmpdir"
      require "securerandom"
      destination = File.join(Dir.tmpdir, "nevaeh-reviewed-#{SecureRandom.hex(16)}")
      result = NevaehIntelligences::ReviewedCandidatePipelineV7a.generate(ticket: ticket, key: key, destination: destination)
      render json: { candidate: true, production_allowed: false, result: result }, status: :created
    rescue StandardError => e
      raise if e.is_a?(CanCan::AccessDenied)
      raise unless allowed_error?(e)
      render json: { error: e.message }, status: :unprocessable_entity
    end
    private
    def authorize_review!
      authorize! :manage, Marlon::Ticket
    end
    def local_only!
      head :forbidden unless NevaehIntelligences::TicketDraftAccessV7a.allowed?
    end
    def allowed_error?(e)
      [ArgumentError, ActiveRecord::RecordNotFound, ActionController::ParameterMissing,
       NevaehIntelligences::ReviewedCandidatePipelineV7a::Rejected,
       NevaehIntelligences::ReviewedImplementationTemplateV7a::Rejected,
       NevaehIntelligences::TicketCapabilityDraftBridgeV7a::Rejected,
       NevaehIntelligences::CapabilityCodeGeneratorV7a::Invalid].any? { |klass| e.is_a?(klass) }
    end
  end
end
