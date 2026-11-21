# frozen_string_literal: true

class Dashboard::ChannelPlayoutController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :load_channel
  rescue_from LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied, ::Gatekeeper::StudioLivePolicy::Denied do |error|
    render plain: error.message, status: :forbidden
  end
  rescue_from ArgumentError, KeyError, ActiveRecord::RecordInvalid, Studio::Broadcasting::HostedPrograms::Unavailable,
    LightekReservations::Federation::Client::Unavailable do |error|
    redirect_to dashboard_channel_playout_path(@channel, site_id: @site.id), alert: error.message, status: :see_other
  end

  def show
    actor = Studio::PwaAccess.new("user_id" => current_user.id, "site_id" => @site.id)
    @videos = StudioAsset.for_actor(actor).where(site_id: @site.id, status: "ready", kind: "video")
      .includes(proxy_attachment: :blob).order(id: :desc).limit(100)
      .select { |asset| asset.proxy.attached? && asset.metadata["duration"].to_f >= 2 }
    @airings = @channel.airings.order(starts_at: :desc).limit(40)
    @inputs = inputs.order(id: :desc).limit(20).select { |operation| input_ready?(operation) }
    @relays = %w[tiktok restream].filter_map do |provider|
      [Studio::Live::Destination.provider!(provider).fetch(:label), provider] if Studio::Live::Destination.configured?(current_user, provider: provider)
    end
    @campaigns = Studio::Advertising::Campaign.for_station(@site.id).includes(:network, asset: { proxy_attachment: :blob })
      .order(:name, :id).limit(100).select(&:creative_available?)
    @ad_placements = Studio::Advertising::Placement.where(airing_id: @airings.select(:id)).includes(:campaign).group_by(&:airing_id)
    @show_projects = StudioProject.where(site_id: @site.id).where.not(owner_id: nil).order(:name, :id)
    @licensed_programs = Studio::Broadcasting::ProgramLicense.where(licensee_site_id: @site.id, status: "accepted")
      .where("ends_at > ?", Time.current).includes(:asset).order(:title, :id)
    @playlist = @channel.managed_path
    @feed_health = Studio::Broadcasting::PlayoutMedia.feed_health(@channel.id)
    @backup_ready = Studio::Broadcasting::PlayoutMedia.backup(@channel).present?
  end

  def create
    raw = params.require(:airing).permit(:title, :starts_at, :weekly_occurrences, :replay, :relay, :show_project_id, rows: %i[kind asset_id seconds label sponsor ad_campaign_id external_ad],
      measurement: Studio::Broadcasting::AudienceReport::INPUT_FIELDS)
    source = raw[:rows]
    rows = source.respond_to?(:values) ? source.values.map(&:to_h) : []
    airings = Studio::Broadcasting::Airing.schedule_weekly!(channel: @channel, operator: current_user, title: raw[:title],
      starts_at: Time.zone.parse(raw[:starts_at].to_s), occurrences: raw[:weekly_occurrences], relay: raw[:relay].presence,
      rows: rows, replay: raw[:replay] == "1", show_project_id: raw[:show_project_id], measurement: raw[:measurement].to_h)
    airings.each { |airing| Studio::Broadcasting::PrepareAiringJob.perform_later(airing.id) }
    back("#{helpers.pluralize(airings.size, "airing")} scheduled. Check preparation status before airtime.")
  end

  def save_backup
    selection = params[:asset_id].presence
    unless selection
      @channel.update!(backup_asset_id: nil, backup_blob_id: nil)
      return back("The channel now uses the default standby slate.")
    end

    actor = Studio::PwaAccess.new("user_id" => current_user.id, "site_id" => @site.id)
    asset = StudioAsset.for_actor(actor).where(site_id: @site.id, status: "ready", kind: "video").find(selection)
    raise ArgumentError, "Choose a ready video with at least two seconds of footage." unless asset.proxy.attached? && asset.metadata["duration"].to_f >= 2

    @channel.update!(backup_asset_id: asset.id, backup_blob_id: asset.proxy.blob.id)
    Studio::Broadcasting::PrepareChannelBackupJob.perform_later(@channel.id, asset.id, asset.proxy.blob.id)
    back("Backup video is preparing. Refresh the channel status to check when it is ready.")
  end

  def command
    airing = @channel.airings.find(params[:airing_id])
    input = inputs.find(params.require(:input_id)) if params[:command] == "break"
    raise ArgumentError, "Start a private channel contribution and wait for it to send video." if input && !input_ready?(input)
    airing.command!(params[:command], input: input)
    back(params[:command] == "cancel" ? "Rundown cancelled." : "Playout change requested.")
  end

  private

  def load_channel
    response.set_header("Cache-Control", "private, no-store")
    ::Gatekeeper::StudioLivePolicy.authorize!(user: current_user)
    @site = Studio::Broadcasting::Access.site(user: current_user, host: request.host, id: params[:site_id])
    raise ActiveRecord::RecordNotFound unless @site
    Studio::Broadcasting::Access.authorize!(current_user, @site)
    @channel = Studio::Broadcasting::Channel.where(site_id: @site.id, managed_playout: true).find(params[:channel_id])
  end

  def inputs
    Studio::Live::Sessions.for_user(current_user).joins(:studio_project)
      .where(status: "live", studio_projects: { site_id: @site.id })
      .where("studio_live_operations.metadata ->> 'destination' = ?", "channel_input")
  end

  def input_ready?(operation)
    operation.updated_at > 25.seconds.ago && Studio::Live::Encoder.hls_path(operation.id).file?
  end

  def back(notice)
    redirect_to dashboard_channel_playout_path(@channel, site_id: @site.id), notice: notice, status: :see_other
  end
end
