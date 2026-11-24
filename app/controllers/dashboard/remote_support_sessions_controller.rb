# frozen_string_literal: true

class Dashboard::RemoteSupportSessionsController < ApplicationController
  protect_from_forgery with: :exception
  before_action :require_direct_session!
  rate_limit to: 60, within: 1.minute, only: :exchange, by: -> { current_user.id }
  rate_limit to: 10, within: 1.minute, only: :create, by: -> { current_user.id }, name: "request"
  before_action :load_room, only: %i[show approve exchange end_session]
  rescue_from Gatekeeper::ItRemoteSupportPolicy::Denied, with: -> { head :forbidden }
  rescue_from ItServices::RemoteScreenShare::Conflict, with: :conflict

  def index
    @available = ItRemoteSupportSession.available?
    return unless @available

    @assigned_requests = ItServiceRequest.where(technician: current_user, status: "in_progress", delivery_mode: "remote")
      .where.not(user_id: current_user.id).order(id: :desc).limit(50)
    @rooms = participant_rooms.includes(:customer, :technician).order(id: :desc).limit(50)
  end

  def show
    @role = Gatekeeper::ItRemoteSupportPolicy.participant!(login: Current.session,
      customer_id: @room.customer_id, technician_id: @room.technician_id)
    @bound = (@role == :customer ? @room.customer_session_id : @room.technician_session_id) == Current.session.id
  end

  def create
    raise ActiveRecord::RecordNotFound unless ItRemoteSupportSession.available?

    work = ItServiceRequest.where(technician: current_user).find(params.require(:request_id))
    ItRemoteSupportSession.open.where(technician_id: current_user.id)
      .or(ItRemoteSupportSession.open.where(customer_id: work.user_id)).where(expires_at: ..Time.current).limit(10).each do |room|
      ItServices::RemoteScreenShare.expire!(room)
    end
    room = ItServices::RemoteScreenShare.request!(work, Current.session)
    schedule_expiry(room)
    redirect_to dashboard_remote_support_session_path(room), status: :see_other
  end

  def approve
    ItServices::RemoteScreenShare.approve!(@room, Current.session)
    schedule_expiry(@room)
    redirect_to dashboard_remote_support_session_path(@room), status: :see_other
  end

  def exchange
    result = ItServices::RemoteScreenShare.exchange!(@room, Current.session, params[:screen_sdp])
    if params[:ice] == true
      result[:ice_servers] = ItServices::RemoteScreenIce.for(@room, current_user.id)
    end
    render json: result
  end

  def end_session
    ItServices::RemoteScreenShare.end!(@room, Current.session)
    respond_to do |format|
      format.html { redirect_to dashboard_remote_support_session_path(@room), status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def schedule_expiry(room)
    ItRemoteSupportExpirationJob.set(wait_until: room.expires_at).perform_later(room.id)
  end

  def require_direct_session!
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Referrer-Policy"] = "same-origin"
    head :forbidden unless Current.session && Current.session.connect_delegation.blank?
  end

  def participant_rooms
    ItRemoteSupportSession.where(customer: current_user).or(ItRemoteSupportSession.where(technician: current_user))
  end

  def load_room
    raise ActiveRecord::RecordNotFound unless ItRemoteSupportSession.available?

    @room = participant_rooms.find(params[:id])
  end

  def conflict(error)
    respond_to do |format|
      format.html { redirect_to dashboard_remote_support_sessions_path, alert: error.message, status: :see_other }
      format.json { render json: { error: error.message }, status: :conflict }
    end
  end
end
