# frozen_string_literal: true
class Dashboard::LiveBroadcastsController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  before_action { ::Gatekeeper::StudioLivePolicy.authorize!(user: current_user) }
  protect_from_forgery with: :exception
  before_action :private_response
  rescue_from ::Gatekeeper::StudioLivePolicy::Denied, LightekCommunity::AccessDenied, LightekPwa::Policy::Denied, with: :denied
  rescue_from Studio::Live::Destination::Unavailable, Studio::Live::Encoder::Failure, Studio::Live::Sessions::Busy, ArgumentError, with: :invalid
  def index
    @encoder_ready = Studio::Live::Encoder.available?
    @restream_ready = Studio::Live::Destination.configured?(current_user, provider: "restream")
    @tiktok_ready = Studio::Live::Destination.configured?(current_user)
    access=LightekCommunity::Access.new(user:current_user,site_id:LightekPwa::SiteContext.resolve(request.host).id)
    @communities=access.communities.select{|community|access.super_admin? || community.member?(current_user.profile)}
    site = LightekPwa::SiteContext.resolve(request.host)
    actor = Studio::PwaAccess.new("user_id"=>current_user.id, "site_id"=>site.id)
    @library_assets = StudioAsset.for_actor(actor).where(site_id: site.id, status: "ready", kind: %w[image audio video]).includes(proxy_attachment: :blob).order(id: :desc).limit(100).select { |asset| asset.proxy.attached? }
    @stage_assets = StudioAsset.for_actor(actor).where(site_id:site.id,status:"ready",kind:%w[blend glb]).includes(proxy_attachment: :blob).order(id: :desc).limit(100).select { |asset| asset.proxy.attached? }
    rooms = LightekSessions::Room.joins(resource: :site).where(status: %w[scheduled open]).where('ends_at > ?', Time.current)
    rooms = rooms.where(lightek_reservation_resources: {site_id: DymondSite::Site.where(tenant: current_user).select(:id)}) unless current_user.role == 'super_admin'
    @session_rooms = rooms.includes(:resource).order(:starts_at).limit(100)
    @restream_chat_url = Studio::Live::Audience.chat_url(current_user)
    @recent = Studio::Live::Sessions.for_user(current_user).order(id: :desc).limit(8)
  end
  def create
    operation = Studio::Live::Sessions.create!(user: current_user, title: params[:title], destination: params[:destination], site: LightekPwa::SiteContext.resolve(request.host), community_slug:params[:community_slug], audience:params.fetch(:audience,"everyone"))
    render json: {id: operation.id, ticket: Studio::Live::Sessions.ticket(operation, current_user), cable_path: "/cable"}, status: :created
  end
  def destination
    provider = params[:provider].presence || "tiktok"
    Studio::Live::Destination.save!(user: current_user, server_url: params[:server_url], stream_key: params[:stream_key], provider: provider)
    redirect_to dashboard_live_path, notice: "#{Studio::Live::Destination.provider!(provider)[:label]} streaming destination stored in Vault. This does not start a broadcast.", status: :see_other
  end
  def audience
    operation = Studio::Live::Sessions.find!(params[:id], current_user)
    render json: Studio::Live::Audience.snapshot(operation, current_user)
  end
  def audience_connection
    source = params.require(:source)
    raise ArgumentError, 'Choose TikTok or Social Stream Ninja.' unless %w[tiktok ssn].include?(source)
    settings = Studio::Live::Audience.settings(current_user)
    raise ArgumentError, 'Save your audience connection settings first.' unless settings[source == 'tiktok' ? 'tiktok_username' : 'ssn_session'].present?
    ticket = Rails.application.message_verifier('studio_audience').generate({'user_id'=>current_user.id, 'source'=>source}, purpose: 'audience_reader', expires_in: 2.minutes)
    render json: {ticket: ticket, cable_path: '/cable'}
  end
  def audience_settings
    Studio::Live::Audience.save!(user: current_user, chat_url: params[:chat_embed_url], tiktok_username: params[:tiktok_username], ssn_session: params[:ssn_session], sign_api_key: params[:sign_api_key])
    redirect_to dashboard_live_path, notice: 'Restream audience chat connected.', status: :see_other
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
