# frozen_string_literal: true
class Dashboard::LiveBroadcastsController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  before_action { ::Gatekeeper::StudioLivePolicy.authorize!(user: current_user) }
  protect_from_forgery with: :exception
  before_action :private_response
  rescue_from ::Gatekeeper::StudioLivePolicy::Denied, LightekCommunity::AccessDenied, LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied, with: :denied
  rescue_from Studio::Live::Destination::Unavailable, Studio::Live::Encoder::Failure, Studio::Live::Sessions::Busy, ArgumentError, with: :invalid
  def index
    @encoder_ready = Studio::Live::Encoder.available?
    @restream_ready = Studio::Live::Destination.configured?(current_user, provider: "restream")
    @tiktok_ready = Studio::Live::Destination.configured?(current_user)
    @site = live_site
    raise ActiveRecord::RecordNotFound unless @site
    access=LightekCommunity::Access.new(user:current_user,site_id:@site.id)
    @communities=access.communities.select{|community|access.super_admin? || community.member?(current_user.profile)}
    site = @site
    @host_package = NevaehOs::LiveShow.for_host!(current_user, site, params[:show_id]) if params[:show_id].present?
    @show_actions = recent_show_actions(site) unless @host_package
    @prepared_scene_id = @host_package ? @host_package['scene_id'] : params[:scene_id]
    @host_destination = @host_package&.fetch('destination')
    if (@host_destination.in?(%w[restream simulcast]) && !@restream_ready) || (@host_destination == 'tiktok' && !@tiktok_ready)
      @host_destination = 'test'
    end
    if site.tenant.is_a?(User)
      demo_site = LightekAgency::DemoSetting.find_by(agency: site.tenant, public_enabled: true)&.public_site
      if demo_site&.tenant == site.tenant && demo_site.host.present?
        @break_demo_url = request_demo_url(host: demo_site.host, protocol: "https", port: nil)
      elsif current_user.role.in?(%w[super_admin white_label]) && LightekAgency::Demos.agencies(current_user).exists?(id: site.tenant_id)
        @break_demo_settings_path = dashboard_demos_path(agency_id: site.tenant_id)
      end
    end
    if defined?(LightekAgency::Trial)
      agency_demo_site = site if LightekAgency::Trial.public_site?(site)
      if !agency_demo_site && current_user.role == 'super_admin'
        agency_demo_site = LightekAgency::Trial.publication_sites(current_user).order(:id).detect { |entry| LightekAgency::Trial.public_site?(entry) }
        @break_agency_settings_path = dashboard_agency_trials_path unless agency_demo_site
      end
      if agency_demo_site
        @break_agency_demo_url = request_agency_demo_url(host: agency_demo_site.host, protocol: 'https', port: nil)
      end
    end
    actor = Studio::PwaAccess.new("user_id"=>current_user.id, "site_id"=>site.id)
    @library_assets = StudioAsset.for_actor(actor).where(site_id: site.id, status: "ready", kind: %w[image audio video]).includes(proxy_attachment: :blob).order(id: :desc).limit(100).select { |asset| asset.proxy.attached? }
    @stage_assets = StudioAsset.for_actor(actor).where(site_id:site.id,status:"ready",kind:%w[blend glb]).includes(proxy_attachment: :blob).order(id: :desc).limit(100).select { |asset| asset.proxy.attached? }
    rooms = LightekSessions::Room.joins(resource: :site).where(status: %w[scheduled open]).where('ends_at > ?', Time.current)
    rooms = rooms.where(lightek_reservation_resources: {site_id: @site.id})
    rooms = rooms.where(host_user_id: current_user.id) unless current_user.role == 'super_admin' || @site.tenant == current_user
    @session_rooms = rooms.includes(:resource).order(:starts_at).limit(100)
    @production_scenes = StudioScene.where(studio_project_id:actor.projects.where(site_id:site.id).select(:id)).includes(:studio_project).order(updated_at: :desc).limit(100).to_a
    if @prepared_scene_id.present?
      selected=Studio::Live::ProductionPreset.new(user:current_user,site:site).scene!(@prepared_scene_id)
      @production_scenes.unshift(selected) unless @production_scenes.any?{|scene|scene.id==selected.id}
    end
    @playout_channels = []
    begin
      Studio::Broadcasting::Access.authorize!(current_user, site)
      @playout_available = true
      @playout_channels = Studio::Broadcasting::Channel.where(site_id: site.id, managed_playout: true).order(:position, :id).to_a
    rescue LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied
      # Live capture can be enabled independently of channel administration.
    end
    @restream_chat_url = Studio::Live::Audience.chat_url(current_user)
    settings = Studio::Live::Audience.settings(current_user)
    @audience_connections = {tiktok: settings['tiktok_username'], ssn: settings['ssn_session'].present?, restream: @restream_chat_url.present?}
    @recent = Studio::Live::Sessions.for_user(current_user).order(id: :desc).limit(8)
  end
  def prepare_show
    site = live_site
    raise ActiveRecord::RecordNotFound unless site

    request_key = params[:request_key].to_s
    raise ArgumentError, 'Reload the show form before assigning it.' unless request_key.match?(/\A[0-9a-f-]{36}\z/)

    fields = params.require(:show).permit(:title, :brief, :destination, :scene_id, :house_look, :subtitle).to_h
    command = { 'kind' => 'live_show', 'site_id' => site.id, 'values' => fields }
    NevaehOs::LiveShow.authorize!(current_user, command)
    goal = NevaehOs::Goals.create!(actor: current_user, request_key: "live-show-#{request_key}",
      values: { 'title' => fields.fetch('title'), 'steps' => [{
        'key' => 'prepare_show', 'agent' => NevaehOs::LiveShow::ROLE, 'command' => command,
        'expectations' => [{ 'path' => 'result.host_path', 'present' => true }]
      }] })
    NevaehOs::Goals.control!(goal: goal, actor: current_user, operation: 'start') if goal.status == 'draft'
    redirect_to dashboard_live_path(site_id: site.id), notice: "Assigned to the Live Broadcast Producer in Goal ##{goal.id}.", status: :see_other
  end
  def production
    site=live_site
    raise ActiveRecord::RecordNotFound unless site
    render json:Studio::Live::ProductionPreset.new(user:current_user,site:site).read(params.require(:scene_id))
  end
  def save_production
    site=live_site
    raise ActiveRecord::RecordNotFound unless site
    preset=params.require(:preset)
    raise ArgumentError,"Live setup must be an object" unless preset.is_a?(ActionController::Parameters)
    render json:Studio::Live::ProductionPreset.new(user:current_user,site:site).save(params.require(:scene_id),preset:preset.to_unsafe_h,lock_version:params.require(:lock_version))
  end
  def create
    site = live_site
    raise ActiveRecord::RecordNotFound unless site
    operation = Studio::Live::Sessions.create!(user: current_user, title: params[:title], destination: params[:destination], site: site, community_slug:params[:community_slug], audience:params.fetch(:audience,"everyone"))
    render json: {id: operation.id, ticket: Studio::Live::Sessions.ticket(operation, current_user), cable_path: "/cable"}, status: :created
  end
  def destination
    provider = params[:provider].presence || "tiktok"
    Studio::Live::Destination.save!(user: current_user, server_url: params[:server_url], stream_key: params[:stream_key], provider: provider)
    redirect_to dashboard_live_path(site_id: params[:site_id]), notice: "#{Studio::Live::Destination.provider!(provider)[:label]} streaming destination stored in Vault. This does not start a broadcast.", status: :see_other
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
    redirect_to dashboard_live_path(site_id: params[:site_id]), notice: 'Audience connection saved. Connect the reader in Audience desk to receive events.', status: :see_other
  end
  def recording
    operation = Studio::Live::Sessions.find!(params[:id], current_user)
    raise ActiveRecord::RecordNotFound unless operation.metadata["destination"] == "test" && operation.status == "ended"
    path = Studio::Live::Encoder.recording_path(operation.id)
    raise ActiveRecord::RecordNotFound unless path.file?
    send_file path, type: "video/mp4", disposition: "attachment", filename: "lightek-live-test-#{operation.id}.mp4"
  end
  private
  def recent_show_actions(site)
    NevaehOsAction.where(user: current_user, status: 'completed')
      .where("command ->> 'kind' = ? AND CAST(command ->> 'site_id' AS TEXT) = ?", 'live_show', site.id.to_s)
      .order(id: :desc).limit(8)
  end

  def live_site
    return LightekPwa::Policy.sites_for(current_user).find(params[:site_id]) if params[:site_id].present?
    LightekPwa::SiteContext.resolve(request.host)
  end
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
      redirect_to dashboard_live_path(site_id: params[:site_id]), alert: error.message, status: :see_other
    end
  end
end
