# frozen_string_literal: true

class Dashboard::BroadcastNetworkController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :load_site
  rescue_from LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied do |error|
    render plain: error.message, status: :forbidden
  end
  rescue_from ArgumentError, KeyError, ActiveRecord::RecordInvalid, Studio::Broadcasting::InstallationCarriage::Unavailable,
    LightekReservations::Federation::Client::Unavailable, Studio::Broadcasting::HostedPrograms::Unavailable do |error|
    redirect_to dashboard_broadcast_network_path(site_id: @site.id), alert: error.message, status: :see_other
  end

  def show
    if @hub && current_user.role == "super_admin"
      @corporate_owner = LightekPwa::Policy.platform_operator(@site)
      @portfolio = LightekPeople::Department.where(employer: @corporate_owner,
        code: LightekPeople::CorporatePortfolio::DIVISIONS.keys).includes(:parent).index_by(&:code) if @corporate_owner && defined?(LightekPeople::Department)
    end
    @channels = channels.order(:position, :id)
    @carriages = carriage.where(channel_id: channels).index_by(&:channel_id)
    @hosted = Studio::Broadcasting::HostedCarriage.where(status: %w[requested accepted]).includes(peer: :site).order(:created_at) if @hub
    @fallback_channels = @channels.where(status: "published") if @hub
    @pending = carriage.where(status: %w[requested accepted]).includes(channel: :site).order(:updated_at) if @hub
    @start_day, @end_day = report_days
    @scope = params[:scope] == "outlet" && @hub ? "outlet" : "station"
    report = audience_report
    @totals = report.totals
    @channel_totals = report.channel_totals
    ids = @channel_totals.map(&:first)
    @channel_names = Studio::Broadcasting::Channel.where(id: ids.select(&:positive?)).pluck(:id, :name).to_h
    Studio::Broadcasting::HostedCarriage.where(id: ids.select(&:negative?).map(&:abs)).pluck(:id, :name)
      .each { |id, name| @channel_names[-id] = name }
    @metadata = report.measurement_metadata
    @outgoing = licensing.where(licensor_site: @site).includes(:licensee_site).order(id: :desc).limit(50)
    @incoming = licensing.where(licensee_site: @site).includes(:licensor_site).order(id: :desc).limit(50)
    @clips = clips.where(withdrawn_at: nil).with_attached_video.order(id: :desc).limit(100).group_by(&:license_id)
    @hosted_program_board = hosted_program_board
    @receiving_sites = receiving_sites.order(:name, :id)
    @assets = assets.includes(proxy_attachment: :blob).order(id: :desc).limit(100).select { |asset| asset.proxy.attached? }
  end

  def install_portfolio
    raise LightekPwa::Policy::Denied, "Only the Lightek platform operator can set up the company portfolio." unless @hub
    LightekPwa::Policy.authorize_platform!(user: current_user, site: @site)
    owner = LightekPwa::Policy.platform_operator(@site)
    raise ArgumentError, "Bind the platform operator to this network site first." unless owner

    LightekPeople::CorporatePortfolio.install!(owner)
    back("Lightek divisions and their reporting lines are available in People.")
  end

  def station_carriage
    channel = channels.find(params[:channel_id])
    entry = carriage.create_or_find_by!(channel: channel)
    connected = Studio::Broadcasting::InstallationCarriage.connected?(@site)
    entry.with_lock do
      entry.update!(remote_key: SecureRandom.hex(16)) if connected && entry.remote_key.nil?
      state = params[:carriage] == "withdraw" ? "withdrawn" : "requested"
      entry.update!(status: state, ownership: nil) unless entry.status == "accepted" && state == "requested"
    end
    Studio::Broadcasting::InstallationCarriage.sync!(entry, renew: params[:carriage] != "withdraw") if connected
    back("Channel carriage updated.")
  end

  def hub_carriage
    raise LightekPwa::Policy::Denied, "Only the network operator can approve carriage." unless @hub

    entry = carriage.find_by!(channel_id: params[:channel_id])
    entry.with_lock do
      if params[:carriage] == "withdraw"
        entry.update!(status: "withdrawn")
      else
        raise ArgumentError, "Ask the station to request carriage again." unless entry.status.in?(%w[requested accepted])
        entry.update!(status: "accepted", ownership: params.require(:ownership))
      end
    end
    back("Network lineup updated.")
  end

  def hosted_carriage
    raise LightekPwa::Policy::Denied, "Only the network operator can approve carriage." unless @hub

    entry = Studio::Broadcasting::HostedCarriage.find_by!(key: params[:key])
    entry.with_lock do
      if params[:carriage] == "withdraw"
        entry.update!(status: "withdrawn")
      else
        raise ArgumentError, "This station needs to request carriage again." unless entry.status.in?(%w[requested accepted]) && entry.peer.active?
        fallback = channels.where(status: "published").find(params[:fallback_channel_id]) if params[:fallback_channel_id].present?
        attributes = { status: "accepted", ownership: params.require(:ownership) }
        attributes[:fallback_channel] = fallback if params.key?(:fallback_channel_id)
        entry.update!(attributes)
      end
    end
    back("Hosted station lineup updated.")
  end

  def offer_license
    values = params.require(:license).permit(:licensee_site_id, :asset_id, :title, :starts_at, :ends_at, additional_rights: [])
    asset = assets.find(values[:asset_id])
    recipient = receiving_sites.find(values[:licensee_site_id])
    licensing.create!(licensor_site: @site, licensee_site: recipient, asset: asset,
      blob_id: asset.proxy.blob&.id, title: values[:title].to_s.strip,
      starts_at: Time.zone.parse(values[:starts_at].to_s), ends_at: Time.zone.parse(values[:ends_at].to_s),
      additional_rights: values.fetch(:additional_rights, []))
    back("Programming rights offered to #{recipient.name}.")
  end

  def offer_hosted_license
    raise ActiveRecord::RecordNotFound unless Studio::Broadcasting::InstallationCarriage.connected?(@site)
    form = params.require(:license).permit(:recipient, :asset_id, :title, :starts_at, :ends_at, additional_rights: [])
    asset = assets.find(form[:asset_id])
    starts_at = Time.zone.parse(form[:starts_at].to_s)
    ends_at = Time.zone.parse(form[:ends_at].to_s)
    raise ArgumentError, "Choose a valid rights window." unless starts_at && ends_at && ends_at > starts_at && ends_at.future?

    Studio::Broadcasting::HostedPrograms.publish!(site: @site, asset: asset, recipient: form[:recipient], title: form[:title].to_s.strip,
      starts_at: starts_at, ends_at: ends_at, additional_rights: form.fetch(:additional_rights, []))
    back("Program offered through the Lightek network.")
  end

  def accept_hosted_license
    raise ActiveRecord::RecordNotFound unless Studio::Broadcasting::InstallationCarriage.connected?(@site)
    Studio::Broadcasting::HostedPrograms.import!(@site, params[:key])
    back("Licensed program downloaded and available in channel rundowns.")
  end

  def withdraw_hosted_license
    raise ActiveRecord::RecordNotFound unless Studio::Broadcasting::InstallationCarriage.connected?(@site)
    Studio::Broadcasting::HostedPrograms.client(@site).request("broadcast/programs/#{params[:key]}/withdraw", method: :post, body: {})
    back("License closed to future bookings.")
  end

  def create_clip
    license = licensing.where(licensee_site: @site, status: "accepted").find(params[:license_id])
    form = params.require(:clip).permit(:title, :start_second, :duration_seconds)
    %i[start_second duration_seconds].each { |field| form[field] = Integer(form.fetch(field).to_s, 10) }
    clip = clips.create!(license: license, **form.to_h.symbolize_keys)
    Studio::Broadcasting::PrepareProgramClipJob.perform_later(clip.id)
    back("Clip queued. Its share link appears after processing.")
  end

  def withdraw_clip
    clips.find(params[:id]).update!(withdrawn_at: Time.current)
    back("Clip removed from public playback.")
  end

  def sublicense
    source = licensing.where(licensee_site: @site, status: "accepted").find(params[:license_id])
    form = params.require(:license).permit(:recipient, :title, :starts_at, :ends_at, additional_rights: [])
    starts_at = Time.zone.parse(form[:starts_at].to_s)
    ends_at = Time.zone.parse(form[:ends_at].to_s)
    raise ArgumentError, "Choose a valid rights window." unless starts_at && ends_at && ends_at > starts_at && ends_at.future?

    attributes = { title: form[:title].to_s.strip, starts_at: starts_at, ends_at: ends_at, additional_rights: form.fetch(:additional_rights, []) }
    if source.imported?
      raise ActiveRecord::RecordNotFound unless Studio::Broadcasting::InstallationCarriage.connected?(@site)
      Studio::Broadcasting::HostedPrograms.client(@site).request("broadcast/programs/#{source.federation_key}/sublicense", method: :post,
        body: attributes.merge(recipient: form[:recipient], starts_at: starts_at.iso8601, ends_at: ends_at.iso8601))
    else
      recipient = receiving_sites.find(form[:recipient])
      source.relicense!(site: @site, recipient: recipient, **attributes)
    end
    back("Programming sublicense offered to the station.")
  end

  def accept_license
    license = licensing.where(licensee_site: @site).find(params[:license_id])
    license.with_lock do
      raise ArgumentError, "This offer is no longer available." unless license.status == "offered" && license.ends_at.future? && license.transferable?
      license.update!(status: "accepted")
    end
    back("Licensed program is available in your channel rundown.")
  end

  def withdraw_license
    license = licensing.where(licensor_site: @site).find(params[:license_id])
    license.update!(status: "withdrawn")
    back("License closed to future bookings. Scheduled airings keep their agreed rights.")
  end

  def audience_csv
    @start_day, @end_day = report_days
    @scope = params[:scope] == "outlet" && @hub ? "outlet" : "station"
    send_data audience_report.csv, type: "text/csv", filename: "broadcast-audience-#{@start_day}-#{@end_day}.csv"
  end

  def measurement_metadata
    @start_day, @end_day = report_days
    @scope = params[:scope] == "outlet" && @hub ? "outlet" : "station"
    render json: { format: "lightek-measurement-metadata-v1", certified: false, timezone: "UTC",
      start_day: @start_day, end_day: @end_day, airings: audience_report.measurement_metadata }
  end

  private

  def load_site
    response.set_header("Cache-Control", "private, no-store")
    @site = Studio::Broadcasting::Access.site(user: current_user, host: request.host, id: params[:site_id])
    raise ActiveRecord::RecordNotFound unless @site
    Studio::Broadcasting::Access.authorize!(current_user, @site)
    @hub = carriage.hub?(@site)
  end

  def hosted_program_board
    return unless Studio::Broadcasting::InstallationCarriage.connected?(@site)

    Studio::Broadcasting::HostedPrograms.board(@site)
  rescue LightekReservations::Federation::Client::Unavailable
    nil
  end

  def participating_site_ids
    Studio::Broadcasting::Channel.where(id: carriage.accepted.select(:channel_id)).select(:site_id)
  end

  def receiving_sites
    hub_host = URI.parse(LightekReservations::Federation::Issuer.origin).host
    scope = DymondSite::Site.where(id: participating_site_ids)
    scope = scope.or(DymondSite::Site.where(host: hub_host))
    scope = scope.or(Studio::Broadcasting::HostedPrograms.directory) if @hub
    scope.where.not(id: @site.id)
  end

  def assets
    actor = Studio::PwaAccess.new("user_id" => current_user.id, "site_id" => @site.id)
    StudioAsset.for_actor(actor).where(site_id: @site.id, kind: "video", status: "ready")
  end

  def channels = Studio::Broadcasting::Channel.where(site_id: @site.id, managed_playout: true)
  def carriage = Studio::Broadcasting::NetworkCarriage
  def clips = Studio::Broadcasting::ProgramClip.where(site: @site)
  def licensing = Studio::Broadcasting::ProgramLicense
  def report_days = [Date.iso8601(params.fetch(:start_day, 6.days.ago.utc.to_date.iso8601)), Date.iso8601(params.fetch(:end_day, Time.current.utc.to_date.iso8601))]
  def audience_report = Studio::Broadcasting::AudienceReport.new(site: @site, start_day: @start_day, end_day: @end_day, outlet: @scope == "outlet")
  def back(notice) = redirect_to(dashboard_broadcast_network_path(site_id: @site.id), notice: notice, status: :see_other)
end
