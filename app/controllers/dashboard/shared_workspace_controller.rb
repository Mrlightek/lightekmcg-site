class Dashboard::SharedWorkspaceController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :load_organization
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }

  private

  def load_organization
    response.headers['Cache-Control'] = 'private, no-store'
    raise LightekPeople::Access::Denied unless current_user

    @employers = LightekTeam::Workspace.employers_for(current_user).order(:id)
    @employer = params[:employer_id].present? ? @employers.find(params[:employer_id]) : @employers.find_by(id: current_user.id) || @employers.first!
    @workspace = LightekTeam::Workspace.new(actor: current_user, employer: @employer)
    @owner = @employer.id == current_user.id
  end

  def owner!
    raise LightekPeople::Access::Denied unless @owner
  end
end
