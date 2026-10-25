# frozen_string_literal: true
module Employee
  class NevaehTicketDraftsController < Employee::ApplicationController
    before_action :authorize_ticket_drafts!
    before_action :require_local_opt_in!

    def index
      @ticket_id = params[:ticket_id].to_s
      @capability_key = params[:key].to_s
      @capabilities = NevaehIntelligences::YamlCapabilityRegistryV7a.list(root: Rails.root.to_s)
      @tickets = Marlon::Ticket.where.not(status: "resolved").order(created_at: :desc).limit(50)
      @preview = if @ticket_id.present? && @capability_key.present?
        ticket = Marlon::Ticket.find(Integer(@ticket_id, 10))
        NevaehIntelligences::TicketCapabilityDraftBridgeV7a.preview(ticket: ticket, capability_key: @capability_key)
      end
      respond_to do |format|
        format.html
        format.json { render json: { preview: @preview, executable: false, production_allowed: false } }
      end
    rescue ArgumentError, ActiveRecord::RecordNotFound, NevaehIntelligences::TicketCapabilityDraftBridgeV7a::Rejected, NevaehIntelligences::YamlCapabilityRegistryV7a::Invalid, NevaehIntelligences::CapabilityCodeGeneratorV7a::Invalid => e
      render plain: "Ticket draft preview rejected: #{e.message}", status: :unprocessable_entity
    end

    def create
      ticket = Marlon::Ticket.find(Integer(params.require(:ticket_id), 10))
      key = params.require(:key).to_s
      require "tmpdir"
      require "securerandom"
      destination = File.join(Dir.tmpdir, "nevaeh-ticket-draft-#{SecureRandom.hex(16)}")
      result = NevaehIntelligences::TicketCapabilityDraftBridgeV7a.generate(ticket: ticket, capability_key: key, destination: destination)
      render json: { draft: true, executable: false, production_allowed: false, result: result }, status: :created
    rescue ArgumentError, ActiveRecord::RecordNotFound, ActionController::ParameterMissing, NevaehIntelligences::TicketCapabilityDraftBridgeV7a::Rejected, NevaehIntelligences::YamlCapabilityRegistryV7a::Invalid, NevaehIntelligences::CapabilityCodeGeneratorV7a::Invalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private
    def authorize_ticket_drafts!
      authorize! :manage, Marlon::Ticket
    end
    def require_local_opt_in!
      # V8_6A_READ_GATE: authenticated super admins may inspect; local opt-in still gates other users.
      head :forbidden unless (action_name == "index" && current_user&.role == "super_admin") || NevaehIntelligences::TicketDraftAccessV7a.allowed?
    end
  end
end
