# frozen_string_literal: true

class Dashboard::NetworkTeamController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :load_installation
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from ArgumentError, LightekReservations::Federation::Client::Unavailable, with: :unavailable

  def index
    @channels = @installation.request('installation/team/list').fetch('channels')
    return unless params[:key].present?

    @channel = @installation.request('installation/team/show', key: params[:key], before: params[:before])
    @users = @installation.members.order(:first_name, :last_name) if @installation.owner? && @channel['status'] == 'connected'
  end

  def change
    operation = params.require(:operation)
    raise LightekPeople::Access::Denied unless operation == 'post' || @installation.owner?

    key = params[:key]
    attributes = case operation
    when 'create' then params.require(:network_channel).permit(:name, :address).to_h.symbolize_keys
    when 'post' then params.require(:network_team_message).permit(:body, :request_key).to_h.symbolize_keys.merge(key: key)
    when 'member'
      user_id = params.require(:user_id).to_s
      raise ArgumentError, 'Choose a teammate.' unless user_id.match?(/\A[1-9]\d{0,18}\z/)

      remove = params[:remove] == '1'
      member = @installation.members.find(user_id) unless remove
      {key: key, member_subject: "user-#{user_id}", display_name: member&.full_name, remove: remove}
    else {key: key}
    end
    result = @installation.request("installation/team/#{operation}", attributes)
    destination = operation == 'disconnect' ? nil : result.fetch('key')
    redirect_to dashboard_network_team_path(key: destination), status: :see_other
  end

  private

  def load_installation
    response.headers['Cache-Control'] = 'private, no-store'
    @installation = LightekTeam::Installation.new(current_user)
  end

  def unavailable(error)
    if action_name == 'index'
      @channels ||= []
      flash.now[:alert] = error.message
      render :index, status: :unprocessable_entity
    else
      redirect_to dashboard_network_team_path(key: params[:key]), alert: error.message, status: :see_other
    end
  end
end
