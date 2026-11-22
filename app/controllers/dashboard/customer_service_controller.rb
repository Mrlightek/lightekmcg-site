# frozen_string_literal: true

class Dashboard::CustomerServiceController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :private_workspace!
  before_action :find_case, only: %i[show reply]
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from NevaehCustomerService::Cases::Invalid, with: :invalid_request

  helper_method :billing_balance

  def index
    @tickets = cases.order(updated_at: :desc, id: :desc).limit(50)
    @installations = support.installations(current_user).order(id: :desc).limit(20)
    @invoices = support.invoices(current_user).order(id: :desc).limit(50)
    @subscriptions = support.subscriptions(current_user).includes(:plan).order(id: :desc).limit(50)
    @overdue_invoices = support.invoices(current_user).where(status: "open")
      .where("amount_remaining_cents > 0 AND due_date < ?", Date.current).order(:due_date, :id).limit(50)
  end

  def show
    @events = @ticket.events.where(action: NevaehCustomerService::Cases::PUBLIC_EVENTS).order(:id)
  end

  def create
    values = params.require(:support_case).permit(:topic, :title, :description, :record_id)
    ticket = support.open!(actor: current_user, topic: values[:topic], title: values[:title],
      description: values[:description], record_id: values[:record_id])
    redirect_to dashboard_customer_case_path(ticket), status: :see_other
  end

  def reply
    support.reply!(ticket: @ticket, actor: current_user, message: params[:message])
    redirect_to dashboard_customer_case_path(@ticket), status: :see_other
  end

  private

  def private_workspace!
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Referrer-Policy"] = "same-origin"
    # Connect sessions can manage the configured installation. This workspace
    # contains the signed-in person's own billing and support history.
    head :forbidden if Current.session&.connect_delegation.present?
  end

  def billing_balance(invoice)
    "#{helpers.number_with_precision(BigDecimal(invoice.amount_remaining_cents) / 100, precision: 2, delimiter: ',')} #{invoice.currency.upcase}"
  end

  def support = NevaehCustomerService::Cases
  def cases = support.customer_scope(current_user)
  def find_case = (@ticket = cases.find(params[:id]))

  def invalid_request(error)
    redirect_to(@ticket ? dashboard_customer_case_path(@ticket) : dashboard_customer_service_path,
      alert: error.message, status: :see_other)
  end
end
