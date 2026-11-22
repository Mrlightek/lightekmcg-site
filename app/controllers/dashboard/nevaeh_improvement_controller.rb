# frozen_string_literal: true

class Dashboard::NevaehImprovementController < Dashboard::NevaehOnboardingController
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }

  def show
    @playbooks = NevaehResolutionPlaybook.where(operator: current_user).order(id: :desc).limit(40)
    @workflows = {
      'agency_onboarding' => 'Paid agency onboarding',
      'purchased_service' => 'Finding a purchased service'
    }
    @agency_mail_ready = NevaehImprovement::Agency.available_for?(current_user)
    @latest_observations = NevaehResolutionObservation.where(operator: current_user).order(id: :desc).limit(25)
  end

  def decide
    revision = NevaehResolutionPlaybook.where(operator: current_user).find(params[:id])
    decision = params.require(:decision)
    return head :unprocessable_entity unless %w[approve decline].include?(decision)

    NevaehImprovement::Cycle.new(current_user, revision.workflow).decide!(revision.id, approve: decision == 'approve')
    redirect_to dashboard_nevaeh_improvement_path, notice: 'Playbook decision recorded.', status: :see_other
  end
end
