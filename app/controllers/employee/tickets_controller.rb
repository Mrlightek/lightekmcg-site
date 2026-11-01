# frozen_string_literal: true
module Employee
  class TicketsController < Employee::ApplicationController
    before_action :set_ticket, only: %i[show reply resolve execute_nevaeh resume_nevaeh edit_nevaeh revise_nevaeh]

    def index
      authorize! :read, Marlon::Ticket
      @tickets = Marlon::Ticket.open_first
      @tickets = @tickets.where(assigned_team: "Technical Team").where("extra_fields ->> 'nevaeh_knowledge_gap' IS NOT NULL") if params[:queue] == "knowledge_gaps"
      @tickets = @tickets.where(status: params[:status]) if params[:status].present?
      @tickets = @tickets.where(category: params[:category]) if params[:category].present?
    end

    def show
      @events = @ticket.events.order(:created_at)
    end

    def new
      @structured_sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name).limit(200)
      authorize! :create, Marlon::Ticket
      @ticket = Marlon::Ticket.new(category: Marlon::TicketCategories.ids.first, priority: "medium", urgency: 5)
    end

    def create
      authorize! :create, Marlon::Ticket
      @ticket = Marlon::Ticket.new(ticket_params)
      @ticket.submitted_by = current_user
      @structured_sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name).limit(200)
      @work_order_values = work_order_params.to_h
      @structured_values = structured_ticket_params.to_h

      begin
        Marlon::Ticket.transaction do
          @ticket.save!
          if params[:request_type] == "knowledge_gap"
            NevaehOrchestration::Escalation.knowledge_gap!(ticket: @ticket, reason: @ticket.description.presence || @ticket.title)
          elsif @structured_values["enabled"] == "1"
            raise NevaehIntelligences::WorkOrder::Invalid, "Choose structured sections or an advanced work order" if @work_order_values["enabled"] == "1"
            authorize! :execute_nevaeh, @ticket if @structured_values["automatic"] == "1"
            NevaehIntelligences::StructuredTicket.attach!(ticket: @ticket, actor: current_user,
              sections: @structured_values.fetch("sections", {}), automatic: @structured_values["automatic"] == "1")
          else
            raise NevaehIntelligences::WorkOrder::Invalid, "Choose an available Knowledge Base procedure for this request"
          end
          @ticket.log!(action: "Ticket submitted", actor: current_user)
        end
      rescue ActiveRecord::RecordInvalid
        return render :new, status: :unprocessable_entity
      rescue NevaehIntelligences::WorkOrder::Invalid, JSON::ParserError => error
        @ticket.errors.add(:base, "Work order: #{error.message}")
        return render :new, status: :unprocessable_entity
      end

      redirect_to employee_ticket_path(@ticket), notice: "Ticket #{@ticket.number} created."
    end

    # Explicit operator-initiated execution; never run during GET or ticket creation.
    def execute_nevaeh
      authorize! :execute_nevaeh, @ticket
      receipt = NevaehIntelligences::WorkOrder.dispatch!(ticket: @ticket, actor: current_user)
      redirect_to employee_ticket_path(@ticket), notice: receipt.is_a?(Hash) ? "Nevaeh dispatched work item #{receipt.fetch('work_item_id')}." : "Nevaeh status: #{receipt}"
    rescue NevaehIntelligences::WorkOrder::Invalid,
           NevaehIntelligences::TicketExecution::InvalidTicket,
           NevaehIntelligences::Dispatch::Unavailable => error
      redirect_to employee_ticket_path(@ticket), alert: "Nevaeh execution blocked: #{error.message}"
    end

    def resume_nevaeh
      authorize! :execute_nevaeh, @ticket
      if @ticket.extra_fields.to_h.dig("nevaeh_work_order", "intent_key") == "ticket.structured.execute"
        NevaehIntelligences::StructuredExecution.resume!(ticket: @ticket, actor: current_user, explicit: true)
      else
        NevaehIntelligences::TicketBacklog.resume!(ticket: @ticket)
      end
      redirect_to employee_ticket_path(@ticket), notice: "Nevaeh processing queued; existing reservations and approvals are preserved."
    rescue NevaehIntelligences::WorkOrder::Invalid => error
      redirect_to employee_ticket_path(@ticket), alert: error.message
    end

    def edit_nevaeh
      authorize! :execute_nevaeh, @ticket
      order = @ticket.extra_fields.to_h["nevaeh_work_order"]
      raise NevaehIntelligences::WorkOrder::Invalid, "Only unreserved support requests can receive a new procedure" if order.to_h["intent_key"] != "ticket.structured.execute" && @ticket.extra_fields.to_h.dig("nevaeh", "reservation_id")
      sections = order.to_h.dig("inputs", "sections") || []
      @structured_sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name).limit(200)
      @structured_values = {"enabled" => "1", "sections" => sections.each_with_index.to_h { |step, index| [index.to_s, step] }}
    end

    def revise_nevaeh
      authorize! :execute_nevaeh, @ticket
      values = structured_ticket_params.to_h
      if (source = @ticket.extra_fields.to_h["nevaeh_github"])
        unless values["source_sha256"] == source["source_sha256"] && values["reviewed_source"] == "1"
          raise NevaehIntelligences::WorkOrder::Invalid, "Review the full GitHub source revision before assigning its procedure"
        end
        @ticket.with_lock do
          fields = @ticket.extra_fields.to_h.deep_stringify_keys
          raise NevaehIntelligences::WorkOrder::Invalid, "GitHub source changed during review" unless fields.dig("nevaeh_github", "source_sha256") == values["source_sha256"]
          fields.fetch("nevaeh_github").delete("revision_requires_review")
          @ticket.update!(extra_fields: fields)
        end
      end
      method = @ticket.extra_fields.to_h.dig("nevaeh_work_order", "intent_key") == "ticket.structured.execute" ? :revise! : :attach!
      NevaehIntelligences::StructuredTicket.public_send(method, ticket: @ticket, actor: current_user,
        sections: values.fetch("sections", {}), automatic: values["automatic"] == "1")
      NevaehIntelligences::ProcessBacklogJob.perform_later(ticket_id: @ticket.id) if method == :attach! && values["automatic"] == "1"
      redirect_to employee_ticket_path(@ticket), notice: "Revision saved. Verified sections were preserved."
    rescue NevaehIntelligences::WorkOrder::Invalid => error
      @structured_sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name).limit(200)
      @structured_values = values
      @ticket.errors.add(:base, error.message)
      render :edit_nevaeh, status: :unprocessable_entity
    end

    def reply
      authorize! :reply, @ticket
      @ticket.log!(action: "#{current_user.full_name} replied", detail: params[:detail], actor: current_user)
      @ticket.update!(status: "in_progress") if @ticket.status == "open"
      redirect_to employee_ticket_path(@ticket), notice: "Reply logged."
    end

    def resolve
      authorize! :resolve, @ticket
      if (@ticket.extra_fields.to_h["nevaeh_knowledge_gap"] || @ticket.extra_fields.to_h.dig("nevaeh_work_order", "intent_key") == "ticket.structured.execute") && @ticket.extra_fields.to_h.dig("nevaeh", "execution_status") != "verified"
        return redirect_to employee_ticket_path(@ticket), alert: "Nevaeh acceptance must pass before this work order can be resolved."
      end
      @ticket.resolve!(actor: current_user)
      redirect_to employee_ticket_path(@ticket), notice: "Ticket resolved."
    end

    private

    def set_ticket
      @ticket = Marlon::Ticket.find(params[:id])
      authorize! :read, @ticket
    end

    def structured_ticket_params
      params.fetch(:structured_ticket, ActionController::Parameters.new).permit(:enabled, :automatic, :source_sha256, :reviewed_source, sections: {})
    end

    def work_order_params
      params.fetch(:work_order, ActionController::Parameters.new).permit(
        :enabled, :work_type, :intent_key, :objective, :inputs_json,
        :acceptance_criteria, :environment, :approval
      )
    end

    def build_work_order(values)
      inputs = JSON.parse(values.fetch("inputs_json", "{}"))
      NevaehIntelligences::WorkOrder.validate!(
        "version" => NevaehIntelligences::WorkOrder::VERSION,
        "work_type" => values.fetch("work_type", "create"),
        "intent_key" => values.fetch("intent_key", "studio.project.create").strip,
        "objective" => values.fetch("objective", "").strip,
        "inputs" => inputs,
        "acceptance_criteria" => values.fetch("acceptance_criteria", "").lines.map(&:strip).reject(&:empty?),
        "execution_policy" => {
          "environment" => values.fetch("environment", "development"),
          "approval" => values.fetch("approval", "gatekeeper")
        }
      )
    end

    def ticket_params
      params.require(:ticket).permit(:category, :title, :description, :priority, :urgency,
                                      :organization_name, :reseller_id, :related_type, :related_id)
    end
  end
end
