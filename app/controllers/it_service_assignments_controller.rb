# frozen_string_literal: true

class ItServiceAssignmentsController < ApplicationController
  before_action :require_login

  def index
    @requests = ItServiceRequest.where(technician: current_user).where(status: %w[scheduled in_progress])
      .includes(:reservation, :user).order(created_at: :desc).limit(100)
  end

  def respond
    request = ItServiceRequest.where(technician: current_user).find(params.require(:id))
    ItServices::TechnicianResponse.call!(request: request, actor: current_user,
      decision: params.require(:decision), note: params.require(:note))
    redirect_to it_service_assignments_path, notice: "Your response was recorded."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to it_service_assignments_path, alert: error.message
  end

  def run_diagnostic
    request = ItServiceRequest.where(technician: current_user).find(params.require(:id))
    report = ItServices::DiagnosticExecution.call!(request: request, technician: current_user,
      code: params.require(:code))
    redirect_to it_service_assignments_path,
      notice: "#{report.fetch('runbook').humanize} metadata review recorded. No remote commands executed."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to it_service_assignments_path, alert: error.message
  end

  def record_work
    request = ItServiceRequest.where(technician: current_user).find(params.require(:id))
    ItServices::TechnicianWork.record!(request: request, actor: current_user,
      step: params.require(:step), result: params.require(:result), evidence: params.require(:evidence))
    redirect_to it_service_assignments_path, notice: "Diagnostic or repair evidence recorded on the Nevaeh ticket."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to it_service_assignments_path, alert: error.message
  end

  def submit_completion
    request = ItServiceRequest.where(technician: current_user).find(params.require(:id))
    ItServices::Completion.submit!(request: request, actor: current_user, summary: params.require(:summary))
    redirect_to it_service_assignments_path, notice: "Completion submitted for customer confirmation."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to it_service_assignments_path, alert: error.message
  end

  private

  def require_login
    head :unauthorized unless current_user
  end
end
