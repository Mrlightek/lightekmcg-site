# frozen_string_literal: true

class Dashboard::TeamChannelsController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :load_workspace
  before_action :load_channel, only: %i[show timeline messages invite remove]
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, with: :invalid_request

  def index
    render :show
  end

  def show
    @reply_to = @channel.messages.find(params[:reply_to]) if params[:reply_to].present?
    @manage_members = @workspace.owner_controls?(@channel)
    if @manage_members
      @memberships = @channel.memberships.includes(:user).order(:id)
      @invitees = @workspace.roster.where.not(id: @channel.memberships.select(:user_id)).order(:first_name, :last_name)
    end
    load_messages
  end

  def timeline
    load_messages
    render partial: 'timeline'
  end

  def create
    attributes = params.require(:team_channel).permit(:name, :description, :private_channel)
    @channel = @workspace.create!(attributes.to_h)
    redirect_to channel_path, notice: 'Channel created.', status: :see_other
  end

  def messages
    attributes = params.require(:team_message).permit(:body, :reply_to_id, :request_key)
    message = @workspace.post!(@channel.id, attributes.to_h)
    redirect_to channel_path(anchor: "team-message-#{message.id}"), status: :see_other
  end

  def invite
    @workspace.change_member!(@channel.id, params.require(:user_id), operation: :add)
    redirect_to channel_path, notice: 'Channel member added.', status: :see_other
  end

  def remove
    @workspace.change_member!(@channel.id, params.require(:user_id), operation: :remove)
    redirect_to channel_path, notice: 'Channel access removed.', status: :see_other
  end

  private

  def load_workspace
    response.set_header('Cache-Control', 'private, no-store')
    return head :unauthorized unless current_user

    @employers = LightekTeam::Workspace.employers_for(current_user).order(:id)
    @employer = params[:employer_id].present? ? @employers.find(params[:employer_id]) : @employers.find_by(id: current_user.id) || @employers.first
    if @employer
      @workspace = LightekTeam::Workspace.new(actor: current_user, employer: @employer)
      @channels = @workspace.channels.order(:name)
    elsif action_name != 'index'
      head :forbidden
    end
  end

  def load_channel
    @channel = @channels.find(params[:id])
  end

  def load_messages
    @query = params[:q].to_s.strip.first(100)
    scope = @channel.messages
    scope = scope.where('id < ?', params[:before].to_i) if params[:before].present?
    if @query.present?
      pattern = ActiveRecord::Base.sanitize_sql_like(@query.downcase)
      scope = scope.where('LOWER(body) LIKE ?', "%#{pattern}%")
    end
    rows = scope.order(id: :desc).limit(41).includes(:author, :reply_to).to_a
    @older_than = rows[39].id if rows.size > 40
    @messages = rows.first(40).reverse
  end

  def channel_path(**options)
    dashboard_team_channel_path(@channel, employer_id: @employer.id, **options)
  end

  def invalid_request(error)
    message = error.is_a?(ActiveRecord::RecordNotUnique) ? 'A channel with that name already exists.' : error.message
    destination = @channel ? channel_path : dashboard_team_channels_path(employer_id: @employer&.id)
    if action_name == 'messages'
      @draft_body = params.dig(:team_message, :body).to_s.first(8_000)
      @draft_key = params.dig(:team_message, :request_key).to_s
      params[:reply_to] = params.dig(:team_message, :reply_to_id)
      flash.now[:alert] = message
      show
      return render :show, status: :unprocessable_entity
    end
    redirect_to destination, alert: message, status: :see_other
  end
end
