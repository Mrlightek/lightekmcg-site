# frozen_string_literal: true

class Dashboard::RemoteSupportSessionsController < ApplicationController
  protect_from_forgery with: :exception
  before_action :require_direct_session!
  rate_limit to: 60, within: 1.minute, only: :exchange, by: -> { current_user.id }
  rate_limit to: 10, within: 1.minute, only: :create, by: -> { current_user.id }, name: "request"
  rate_limit to: 12, within: 1.minute, only: %i[offer_file accept_file cancel_file download_file],
    by: -> { current_user.id }, name: "files"
  before_action :load_room, only: %i[show approve exchange end_session offer_file accept_file cancel_file download_file]
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
    @transfers = @room.transfers.order(:id)
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
    result = ItServices::RemoteScreenShare.exchange!(@room, Current.session, params[:screen_sdp],
      display_reported: params[:display_reported] == true)
    if params[:ice] == true
      result[:ice_servers] = ItServices::RemoteScreenIce.for(@room, current_user.id)
    end
    render json: result
  end

  def offer_file
    transfer = files.offer!(@room, Current.session, params[:support_file])
    ItRemoteSupportFileScanJob.perform_later(transfer.id)
    redirect_to dashboard_remote_support_session_path(@room), status: :see_other
  end

  def accept_file
    files.accept!(@room, Current.session, params.require(:transfer_id))
    redirect_to dashboard_remote_support_session_path(@room), status: :see_other
  end

  def cancel_file
    files.cancel!(@room, Current.session, params.require(:transfer_id))
    redirect_to dashboard_remote_support_session_path(@room), status: :see_other
  end

  def download_file
    file = files.download!(@room, Current.session, params.require(:transfer_id))
    response.headers["X-File-SHA256"] = file.fetch(:sha256)
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_data file.fetch(:bytes), filename: file.fetch(:filename), type: "application/octet-stream", disposition: "attachment"
  end

  def end_session
    ItServices::RemoteScreenShare.end!(@room, Current.session)
    respond_to do |format|
      format.html { redirect_to dashboard_remote_support_session_path(@room), status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def files = ItServices::RemoteSupportFiles

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
      format.html do
        destination = @room ? dashboard_remote_support_session_path(@room) : dashboard_remote_support_sessions_path
        redirect_to destination, alert: error.message, status: :see_other
      end
      format.json { render json: { error: error.message }, status: :conflict }
    end
  end
end
