# frozen_string_literal: true
module Employee
  class TicketsController < Employee::ApplicationController
    before_action :set_ticket, only: %i[show reply resolve]

    def index
      authorize! :read, Marlon::Ticket
      @tickets = Marlon::Ticket.open_first
      @tickets = @tickets.where(status: params[:status]) if params[:status].present?
      @tickets = @tickets.where(category: params[:category]) if params[:category].present?
    end

    def show
      @events = @ticket.events.order(:created_at)
    end

    def new
      @ticket = Marlon::Ticket.new(category: Marlon::TicketCategories.ids.first, priority: "medium", urgency: 5)
    end

    def create
      @ticket = Marlon::Ticket.new(ticket_params)
      @ticket.submitted_by = current_user
      if @ticket.save
        @ticket.log!(action: "Ticket submitted", actor: current_user)
        redirect_to employee_ticket_path(@ticket), notice: "Ticket #{@ticket.number} created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def reply
      @ticket.log!(action: "#{current_user.full_name} replied", detail: params[:detail], actor: current_user)
      @ticket.update!(status: "in_progress") if @ticket.status == "open"
      redirect_to employee_ticket_path(@ticket), notice: "Reply logged."
    end

    def resolve
      @ticket.resolve!(actor: current_user)
      redirect_to employee_ticket_path(@ticket), notice: "Ticket resolved."
    end

    private

    def set_ticket
      @ticket = Marlon::Ticket.find(params[:id])
      authorize! :read, @ticket
    end

    def ticket_params
      params.require(:ticket).permit(:category, :title, :description, :priority, :urgency,
                                      :organization_name, :reseller_id, :related_type, :related_id)
    end
  end
end
