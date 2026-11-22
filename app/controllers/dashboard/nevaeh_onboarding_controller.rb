# frozen_string_literal: true

class Dashboard::NevaehOnboardingController < ApplicationController
  layout 'dymond_dash/layouts/dymond_dash'
  protect_from_forgery with: :exception
  before_action :authorize_operator

  def show
    scope = NevaehOnboardingCase.where(operator: current_user)
    @attention = scope.open_cases.where.not(escalated_at: nil).order(:escalated_at, :id).limit(30)
    @in_progress = scope.open_cases.where(escalated_at: nil).count
    @complete = scope.where.not(completed_at: nil).count
    @playbooks = NevaehOnboardingPlaybook.where(operator: current_user).order(id: :desc).limit(15)
  end

  def approve
    improvement.promote!(params[:id])
    redirect_to dashboard_nevaeh_onboarding_path, notice: 'Approved for a controlled rollout.', status: :see_other
  end

  def reject
    improvement.reject!(params[:id])
    redirect_to dashboard_nevaeh_onboarding_path, notice: 'Playbook proposal declined.', status: :see_other
  end

  private

  def authorize_operator
    response.set_header('Cache-Control', 'private, no-store')
    head :forbidden unless NevaehOnboarding::StandingAssignment.operator?(current_user) && Current.session.connect_delegation.blank?
  end

  def improvement = NevaehOnboarding::Improvement.new(current_user)
end
