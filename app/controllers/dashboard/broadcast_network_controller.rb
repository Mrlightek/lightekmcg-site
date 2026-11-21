# frozen_string_literal: true

class Dashboard::BroadcastNetworkController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :load_site
  rescue_from LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied do |error|
    render plain: error.message, status: :forbidden
  end
  rescue_from ArgumentError, ActiveRecord::RecordInvalid do |error|
    redirect_to dashboard_broadcast_network_path(site_id: @site.id), alert: error.message, status: :see_other
  end

  def show
    @channels = channels.order(:position, :id)
    @carriages = carriage.where(channel_id: channels).index_by(&:channel_id)
    @pending = carriage.where(status: %w[requested accepted]).includes(channel: :site).order(:updated_at) if @hub
    @start_day, @end_day = report_days
    @scope = params[:scope] == "outlet" && @hub ? "outlet" : "station"
    report = audience_report
    @totals = report.totals
    @channel_totals = report.channel_totals
    @channel_names = Studio::Broadcasting::Channel.where(id: @channel_totals.map(&:first)).pluck(:id, :name).to_h
    @metadata = report.measurement_metadata
    @outgoing = licensing.where(licensor_site: @site).includes(:licensee_site).order(id: :desc).limit(50)
    @incoming = licensing.where(licensee_site: @site).includes(:licensor_site).order(id: :desc).limit(50)
    @receiving_sites = receiving_sites.order(:name, :id)
    @assets = assets.includes(proxy_attachment: :blob).order(id: :desc).limit(100).select { |asset| asset.proxy.attached? }
  end

  def station_carriage
    channel = channels.find(params[:channel_id])
    entry = carriage.create_or_find_by!(channel: channel)
    entry.with_lock do
      state = params[:carriage] == "withdraw" ? "withdrawn" : "requested"
      entry.update!(status: state, ownership: nil) unless entry.status == "accepted" && state == "requested"
    end
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

  def offer_license
    values = params.require(:license).permit(:licensee_site_id, :asset_id, :title, :starts_at, :ends_at)
    asset = assets.find(values[:asset_id])
    recipient = receiving_sites.find(values[:licensee_site_id])
    licensing.create!(licensor_site: @site, licensee_site: recipient, asset: asset,
      blob_id: asset.proxy.blob&.id, title: values[:title].to_s.strip,
      starts_at: Time.zone.parse(values[:starts_at].to_s), ends_at: Time.zone.parse(values[:ends_at].to_s))
    back("Programming rights offered to #{recipient.name}.")
  end

  def accept_license
    license = licensing.where(licensee_site: @site).find(params[:license_id])
    license.with_lock do
      raise ArgumentError, "This offer is no longer available." unless license.status == "offered" && license.ends_at.future?
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

  def participating_site_ids
    Studio::Broadcasting::Channel.where(id: carriage.accepted.select(:channel_id)).select(:site_id)
  end

  def receiving_sites
    hub_host = URI.parse(LightekReservations::Federation::Issuer.origin).host
    scope = DymondSite::Site.where(id: participating_site_ids)
    scope.or(DymondSite::Site.where(host: hub_host)).where.not(id: @site.id)
  end

  def assets
    actor = Studio::PwaAccess.new("user_id" => current_user.id, "site_id" => @site.id)
    StudioAsset.for_actor(actor).where(site_id: @site.id, kind: "video", status: "ready")
  end

  def channels = Studio::Broadcasting::Channel.where(site_id: @site.id, managed_playout: true)
  def carriage = Studio::Broadcasting::NetworkCarriage
  def licensing = Studio::Broadcasting::ProgramLicense
  def report_days = [Date.iso8601(params.fetch(:start_day, 6.days.ago.utc.to_date.iso8601)), Date.iso8601(params.fetch(:end_day, Time.current.utc.to_date.iso8601))]
  def audience_report = Studio::Broadcasting::AudienceReport.new(site: @site, start_day: @start_day, end_day: @end_day, outlet: @scope == "outlet")
  def back(notice) = redirect_to(dashboard_broadcast_network_path(site_id: @site.id), notice: notice, status: :see_other)
end
