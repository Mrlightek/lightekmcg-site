# frozen_string_literal: true
class Dashboard::LiveBroadcastsController < Dashboard::SettingsHomeController
  protect_from_forgery with: :exception
  before_action :private_response
  rescue_from ::Gatekeeper::StudioLivePolicy::Denied, with: :denied
  rescue_from Studio::Live::Destination::Unavailable, Studio::Live::Encoder::Failure, Studio::Live::Sessions::Busy, ArgumentError, with: :invalid
  def index
    @encoder_ready = Studio::Live::Encoder.available?
    @restream_ready = Studio::Live::Destination.configured?(current_user, provider: "restream")
    @tiktok_ready = Studio::Live::Destination.configured?(current_user)
    @recent = Studio::Live::Sessions.for_user(current_user).order(id: :desc).limit(8)
  end
  def create
    operation = Studio::Live::Sessions.create!(user: current_user, title: params[:title], destination: params[:destination])
    render json: {id: operation.id, ticket: Studio::Live::Sessions.ticket(operation, current_user), cable_path: "/cable"}, status: :created
  end
  def destination
    provider = params[:provider].presence || "tiktok"
    Studio::Live::Destination.save!(user: current_user, server_url: params[:server_url], stream_key: params[:stream_key], provider: provider)
    redirect_to dashboard_live_path, notice: "#{Studio::Live::Destination.provider!(provider)[:label]} streaming destination stored in Vault. This does not start a broadcast.", status: :see_other
  end
  def recording
    operation = Studio::Live::Sessions.find!(params[:id], current_user)
    raise ActiveRecord::RecordNotFound unless operation.metadata["destination"] == "test" && operation.status == "ended"
    path = Studio::Live::Encoder.recording_path(operation.id)
    raise ActiveRecord::RecordNotFound unless path.file?
    send_file path, type: "video/mp4", disposition: "attachment", filename: "lightek-live-test-#{operation.id}.mp4"
  end
  private
  def private_response
    response.set_header("Cache-Control", "private, no-store")
  end
  def denied(error)
    render json: {error: error.message}, status: :forbidden
  end
  def invalid(error)
    if request.format.json?
      render json: {error: error.message}, status: :unprocessable_entity
    else
      redirect_to dashboard_live_path, alert: error.message, status: :see_other
    end
  end
end
