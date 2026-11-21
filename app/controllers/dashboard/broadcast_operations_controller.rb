# frozen_string_literal: true

require "csv"

class Dashboard::BroadcastOperationsController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :load_site

  rescue_from LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied do |error|
    render plain: error.message, status: :forbidden
  end
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, LightekReservations::Federation::Client::Unavailable do |error|
    redirect_to dashboard_broadcast_operations_path(site_id: @site.id), alert: error.message, status: :see_other
  end

  def show
    @channels = local_channels.order(:position, :id)
    @agreements = agreements.where(outlet_site: @site).or(agreements.where(station_site: @site))
      .includes(:channel, :hosted_carriage, :outlet_site, :station_site, :accepted_by).order(id: :desc).limit(100)
    if @hub && @admin
      @offer_choices = offer_channels.includes(:site).order(:name, :id).map do |channel|
        ["#{channel.site.name} · #{channel.name}", channel.id]
      end
      @offer_choices += hosted_channels.includes(peer: :site).order(:name, :id).map do |entry|
        ["#{entry.peer.site.name} · #{entry.name} (hosted)", "hosted-#{entry.id}"]
      end
    elsif Studio::Broadcasting::InstallationCarriage.connected?(@site)
      load_hosted_agreements
    end
    if @admin
      @packages = packages.order(id: :desc).limit(50)
      @payments = Studio::Advertising::SponsorPackage.sellable_payments(@site).where(state: "unfunded")
        .includes(placement: [:station_site, :campaign, { airing: :channel }]).order(id: :desc).limit(150)
        .select { |payment| payment.placement.payable_airing? && payment.placement.booked_start&.future? }
    end
    if @employer
      @departments = departments.order(:name, :id)
      @owners = User.where(id: [@employer.id] + active_worker_ids).order(:id)
      @plans = plans.includes(:department, :owner, :channel).order(month: :desc, id: :desc).limit(60)
    end
  end

  def offer_agreement
    require_admin!
    raise LightekPwa::Policy::Denied, "The network operator offers carriage agreements." unless @hub

    form = params.require(:agreement).permit(:channel_id, :starts_on, :ends_on, terms: Studio::Broadcasting::CarriageAgreement::TERMS.keys)
    selection = form[:channel_id].to_s
    if selection.start_with?("hosted-")
      hosted = hosted_channels.find(selection.delete_prefix("hosted-"))
      channel = nil
      station = hosted.peer.site
    else
      channel = offer_channels.find(selection)
      station = channel.site
    end
    agreements.create!(outlet_site: @site, station_site: station, channel: channel, hosted_carriage: hosted,
      offered_by: current_user, starts_on: Date.iso8601(form[:starts_on].to_s), ends_on: Date.iso8601(form[:ends_on].to_s),
      terms: form[:terms]&.to_h)
    back("Terms sent to the station’s Network operations dashboard.")
  end

  def accept_agreement
    require_admin!
    agreements.where(station_site: @site).find(params[:id]).accept!(site: @site, actor: current_user)
    back("Carriage agreement accepted.")
  end

  def accept_hosted_agreement
    require_admin!
    raise ActiveRecord::RecordNotFound unless Studio::Broadcasting::InstallationCarriage.connected?(@site)

    federation.request("broadcast/agreements/#{Integer(params[:id])}/accept", method: :post, body: {})
    back("Hosted carriage agreement accepted.")
  end

  def create_package
    require_admin!
    form = params.require(:package).permit(:name, payment_ids: [])
    Studio::Advertising::SponsorPackage.book!(site: @site, name: form[:name], payment_ids: form.fetch(:payment_ids, []))
    back("Sponsor package created. Share its private checkout and delivery link with the sponsor.")
  end

  def package_report
    require_admin!
    package = packages.find(params[:id])
    csv = CSV.generate do |data|
      data << %w[spot payment_id station channel campaign scheduled_at delivered_at payment_status amount_usd station_payout producer_payout network_payout]
      package.report_payments.each do |payment|
        spot = payment.placement
        names = [spot.station_site.name, spot.airing&.channel&.name, spot.campaign.name].map do |name|
          value = name.to_s
          value.match?(/\A[[:space:]]*[=+@-]|\A[\t\r\n]/) ? "'#{value}" : value
        end
        payouts = payment.payouts.index_by(&:role)
        data << [spot.id, payment.id, *names, spot.booked_start&.utc&.iso8601, spot.delivered_at&.utc&.iso8601, payment.state,
          format("%.2f", payment.amount_cents / 100.0), *%w[station producer network].map { |role| payout_status(payouts[role]) }]
      end
    end
    send_data csv, filename: "sponsor-package-#{package.id}.csv", type: "text/csv"
  end

  def save_plan
    raise LightekPwa::Policy::Denied, "Only employer leadership can manage operating plans." unless @employer

    form = params.require(:plan).permit(:department_id, :owner_id, :channel_id, :market, :month, :coverage, :targets,
      *Studio::Broadcasting::OperatingPlan::MONEY_FIELDS)
    plan = params[:id] ? plans.find(params[:id]) : plans.new
    department = departments.find(form[:department_id])
    owner = User.where(id: [@employer.id] + active_worker_ids).find(form[:owner_id])
    channel = local_channels.find(form[:channel_id]) if form[:channel_id].present?
    raise ArgumentError, "Enter a budget month." unless form[:month].to_s.match?(/\A\d{4}-\d{2}\z/)

    amounts = Studio::Broadcasting::OperatingPlan::MONEY_FIELDS.to_h do |field|
      value = form[field].to_s.strip
      raise ArgumentError, "Enter each dollar amount with at most two decimal places." unless value.match?(/\A\d{1,9}(?:\.\d{1,2})?\z/)

      whole, fraction = value.split(".")
      ["#{field}_cents", whole.to_i * 100 + fraction.to_s.ljust(2, "0").to_i]
    end
    plan.update!(department: department, owner: owner, channel: channel, month: Date.iso8601("#{form[:month]}-01"),
      market: form[:market].to_s.strip.presence, coverage: form[:coverage], targets: form[:targets], **amounts)
    back("Monthly operating plan saved.")
  end

  private

  def load_site
    response.set_header("Cache-Control", "private, no-store")
    @site = Studio::Broadcasting::Access.site(user: current_user, host: request.host, id: params[:site_id])
    raise ActiveRecord::RecordNotFound unless @site

    Studio::Broadcasting::Access.authorize!(current_user, @site)
    @admin = LightekPwa::Policy.new(user: current_user, site: @site).role == "admin"
    @hub = Studio::Broadcasting::NetworkCarriage.hub?(@site)
    employer = @hub ? LightekPwa::Policy.platform_operator(@site) : @site.tenant
    @employer = employer if employer.is_a?(User) && employer.id == current_user.id
  end

  def require_admin!
    raise LightekPwa::Policy::Denied, "Site administrator access required." unless @admin
  end

  def payout_status(payout)
    return "none" unless payout
    return "reversed" if payout.reversal_reference?
    return "transferred" if payout.transfer_reference?

    "pending"
  end

  def load_hosted_agreements
    @hosted_agreements = federation.request("broadcast/agreements").fetch("agreements")
  rescue LightekReservations::Federation::Client::Unavailable
    @hosted_agreements_unavailable = true
  end

  def federation = LightekReservations::Federation::Client.new(@site)
  def hosted_channels = Studio::Broadcasting::HostedCarriage.where(status: %w[requested accepted])

  def offer_channels
    Studio::Broadcasting::Channel.where(id: Studio::Broadcasting::NetworkCarriage.where(status: %w[requested accepted]).select(:channel_id),
      managed_playout: true).where.not(site_id: @site.id)
  end

  def agreements = Studio::Broadcasting::CarriageAgreement
  def packages = Studio::Advertising::SponsorPackage.where(site: @site)
  def plans = Studio::Broadcasting::OperatingPlan.where(site: @site)
  def departments = LightekPeople::Department.where(employer: @employer, active: true)
  def active_worker_ids = LightekPeople::Employment.active.where(employer: @employer).pluck(:worker_id)
  def local_channels = Studio::Broadcasting::Channel.where(site: @site, managed_playout: true)
  def back(notice) = redirect_to(dashboard_broadcast_operations_path(site_id: @site.id), notice: notice, status: :see_other)
end
