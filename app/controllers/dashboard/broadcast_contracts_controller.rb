# frozen_string_literal: true

class Dashboard::BroadcastContractsController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :private_response
  before_action :load_contract, only: %i[show revise sign withdraw record_evidence report executed_copy]
  before_action :load_version, only: %i[sign withdraw record_evidence report executed_copy]

  rescue_from ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ArgumentError, KeyError,
    LightekReservations::Federation::Client::Unavailable do |error|
    redirect_to dashboard_broadcast_contracts_path(site_id: @site&.id), alert: error.message, status: :see_other
  end
  rescue_from LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied do |error|
    render plain: error.message, status: :forbidden
  end

  def index
    @site = current_site
    begin
      authorize_site!(@site) if @site
    rescue LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied
      raise if params[:site_id].present?

      @site = nil
    end
    outgoing = @site ? BroadcastContract.where(site: @site).includes(:versions).order(id: :desc) : BroadcastContract.none
    @outgoing = outgoing.limit(100)
    @incoming = BroadcastContract.incoming(current_user).where.not(id: outgoing.select(:id)).includes(:versions).order(id: :desc).limit(100)
    @renewals = renewal_versions(outgoing.or(BroadcastContract.where(id: @incoming.map(&:id))))
    return unless @site

    @carriages = CarriageAgreement.where(outlet_site: @site).where.not(id: BroadcastContract.select(:carriage_agreement_id).where.not(carriage_agreement_id: nil))
      .includes(:channel, :hosted_carriage, :station_site).order(id: :desc).limit(100)
    @packages = SponsorPackage.where(site: @site).where.not(id: BroadcastContract.select(:sponsor_package_id).where.not(sponsor_package_id: nil))
      .order(id: :desc).limit(100)
    @archives = BroadcastReportArchive.where(site: @site).order(month: :desc).limit(24) if plan_owner?
    if Studio::Broadcasting::InstallationCarriage.connected?(@site) && !Studio::Broadcasting::NetworkCarriage.hub?(@site)
      @hosted = federation.request("broadcast/agreements").fetch("agreements").select { |record| record["contract"].present? }
    end
  rescue LightekReservations::Federation::Client::Unavailable
    @hosted_unavailable = true
  end

  def create
    require_site!
    form = params.require(:contract).permit(:kind, :title, :counterparty_email, :source_id)
    kind = form.fetch(:kind)
    direct = %w[sponsor producer].include?(kind)
    person = User.find_by!(email_address: form[:counterparty_email].to_s.strip.downcase) if direct
    raise ArgumentError, "Choose a different account as counterparty." if person == current_user

    carriage = CarriageAgreement.where(outlet_site: @site).find(form[:source_id]) if kind == "carriage"
    package = SponsorPackage.where(site: @site).find(form[:source_id]) if kind == "sponsor"
    BroadcastContract.transaction do
      @contract = BroadcastContract.create!(site: @site, kind: kind, title: form[:title], counterparty: person,
        carriage_agreement: carriage, sponsor_package: package)
      @contract.offer!(actor: current_user, **offer_terms)
    end
    back("Agreement offered.")
  end

  def show
    @versions = @contract.versions.includes(:signatures).order(number: :desc)
    @version = if params[:version_id]
      @versions.find(params[:version_id])
    else
      @versions.find { |version| version.executed? && version.starts_on <= Date.current } || @versions.first
    end
    @report = ContractReport.new(version: @version).snapshot
    @evidence_kinds = BroadcastContractEvidence::KINDS
    @evidence_kinds = @evidence_kinds.except("delivery") if @version.terms_snapshot["delivery_mode"] == "booked_spots"
  end

  def revise
    require_issuer!
    @contract.offer!(actor: current_user, **offer_terms)
    redirect_to dashboard_broadcast_contract_path(@contract, site_id: @site.id, version_id: @contract.versions.maximum(:id)),
      notice: "New version offered. Existing executed versions remain available.", status: :see_other
  end

  def sign
    confirm = params.require(:signature).permit(:name, :digest, :consent)
    raise ArgumentError, "Confirm your intent to sign." unless confirm[:consent] == "1"
    @version.sign!(actor: current_user, party: @party, name: confirm[:name], digest: confirm[:digest])
    back(@version.executed? ? "Agreement executed." : "Signature recorded. The other party still needs to sign.")
  end

  def withdraw
    require_issuer!
    @version.withdraw!
    back("Unsigned offer withdrawn.")
  end

  def record_evidence
    require_issuer!
    form = params.require(:evidence).permit(:kind, :reference, :quantity, :occurred_on)
    quantity = form[:kind] == "reviewed_payment" ? cents(form[:quantity]) : Integer(form[:quantity].to_s, 10)
    @contract.with_lock do
      @version.evidence.create!(kind: form[:kind], reference: form[:reference].to_s.strip, quantity: quantity,
        occurred_on: Date.iso8601(form[:occurred_on].to_s), recorded_by: current_user)
    end
    back("Evidence recorded.")
  end

  def report
    send_data ContractReport.csv([ContractReport.new(version: @version).snapshot]), filename: "agreement-#{@contract.id}-v#{@version.number}.csv", type: "text/csv"
  end

  def executed_copy
    send_data @version.executed_copy, filename: "agreement-#{@contract.id}-v#{@version.number}.txt", type: "text/plain"
  end

  def portfolio_report
    require_site!
    send_data ContractReport.csv(ContractReport.for_site(@site)), filename: "broadcast-agreement-performance.csv", type: "text/csv"
  end

  def carriage_report
    require_site!
    agreement = CarriageAgreement.where(outlet_site: @site).or(CarriageAgreement.where(station_site: @site, hosted_carriage_id: nil)).find(params[:id])
    send_data ContractReport.csv([ContractReport.new(carriage: agreement).snapshot]), filename: "carriage-#{agreement.id}.csv", type: "text/csv"
  end

  def license_report
    require_site!
    source = Studio::Broadcasting::ProgramLicense
    license = source.where(licensor_site: @site).or(source.where(licensee_site: @site)).find(params[:id])
    send_data ContractReport.csv([ContractReport.program_license(license)]), filename: "program-license-#{license.id}.csv", type: "text/csv"
  end

  def hosted
    require_station_connection!
    @hosted_agreement = federation.request(hosted_endpoint)
    @report = @hosted_agreement.fetch("report")
  end

  def sign_hosted
    require_station_connection!
    signature = params.require(:signature).permit(:version_id, :name, :digest, :consent)
    federation.request("#{hosted_endpoint}/sign", method: :post, body: { signature: signature.to_h })
    redirect_to dashboard_hosted_broadcast_contract_path(params[:id], site_id: @site.id), notice: "Signature recorded.", status: :see_other
  end

  def hosted_document
    require_station_connection!
    document = federation.request("#{hosted_endpoint}/#{params[:document]}")
    body = params[:document] == "report" ? ContractReport.csv([document.fetch("report")]) : document.fetch("copy")
    csv = params[:document] == "report"
    send_data body, filename: "hosted-agreement-#{Integer(params[:id])}.#{csv ? 'csv' : 'txt'}", type: csv ? "text/csv" : "text/plain"
  end

  def network
    require_site!
    first = Date.iso8601(params.fetch(:from, 6.days.ago.utc.to_date.iso8601))
    last = Date.iso8601(params.fetch(:through, Time.current.utc.to_date.iso8601))
    @show_operating_plans = plan_owner?
    @network = NetworkReport.new(site: @site, first: first, last: last, include_plans: @show_operating_plans, include_network_finance: @show_operating_plans)
    if params[:format] == "csv"
      send_data @network.csv, filename: "network-#{first}-#{last}.csv", type: "text/csv"
    else
      @audience = @network.audience
      @reliability = @network.reliability
      @incidents = @network.feed_incidents
      @finance = @network.finance
      @plans = @network.plans
      if @show_operating_plans
        @delivery_costs = @network.delivery_costs
        @delivery_rates = Studio::Broadcasting::DeliveryRate.find_or_initialize_by(site_id: @site.id)
        @delivery_channels = Studio::Broadcasting::Channel.where(site: @site).order(:name)
      end
    end
  end

  def delivery_rates
    require_site!
    raise ActiveRecord::RecordNotFound unless plan_owner?

    rate = Studio::Broadcasting::DeliveryRate.find_or_initialize_by(site_id: @site.id)
    rate.update!(params.require(:delivery_rate).permit(*Studio::Broadcasting::DeliveryRate::UNITS.keys))
    redirect_to dashboard_broadcast_network_report_path(site_id: @site.id), notice: "Delivery cost rates saved.", status: :see_other
  end

  def delivery_support
    require_site!
    raise ActiveRecord::RecordNotFound unless plan_owner?

    channel = Studio::Broadcasting::Channel.where(site: @site).find(params[:channel_id])
    minutes = Integer(params[:minutes].to_s, 10)
    raise ArgumentError, "Enter support minutes between 1 and 1440." unless minutes.between?(1, 1440)

    Studio::Broadcasting::DeliveryUsage.record!(site_id: @site.id, channel_key: channel.id, metric: :support_minutes, amount: minutes)
    redirect_to dashboard_broadcast_network_report_path(site_id: @site.id), notice: "Support time recorded.", status: :see_other
  end

  def archive
    require_site!
    raise ActiveRecord::RecordNotFound unless plan_owner?

    row = BroadcastReportArchive.where(site: @site).find(params[:id])
    send_data row.csv, filename: "network-#{row.month.strftime('%Y-%m')}.csv", type: "text/csv"
  end

  private

  BroadcastContract = Studio::Broadcasting::BroadcastContract
  BroadcastContractVersion = Studio::Broadcasting::BroadcastContractVersion
  BroadcastContractEvidence = Studio::Broadcasting::BroadcastContractEvidence
  BroadcastReportArchive = Studio::Broadcasting::BroadcastReportArchive
  CarriageAgreement = Studio::Broadcasting::CarriageAgreement
  ContractReport = Studio::Broadcasting::ContractReport
  NetworkReport = Studio::Broadcasting::NetworkReport
  SponsorPackage = Studio::Advertising::SponsorPackage
  Access = Studio::Broadcasting::Access

  def private_response
    response.set_header("Cache-Control", "private, no-store")
    raise ActiveRecord::RecordNotFound unless current_user
  end

  def current_site = Access.site(user: current_user, host: request.host, id: params[:site_id])

  def authorize_site!(site)
    Access.authorize!(current_user, site)
    raise LightekPwa::Policy::Denied, "A site administrator must manage agreements and financial reports." unless
      LightekPwa::Policy.new(user: current_user, site: site).role == "admin"
  end

  def require_site!
    @site = current_site
    raise ActiveRecord::RecordNotFound unless @site

    authorize_site!(@site)
  end

  def load_contract
    @site = current_site if params[:site_id].present?
    authorize_site!(@site) if @site
    outgoing = @site ? BroadcastContract.where(site: @site) : BroadcastContract.none
    @contract = outgoing.or(BroadcastContract.incoming(current_user)).find(params[:id])
    if @site && @contract.site_id == @site.id
      @party = "issuer"
    else
      authorize_site!(@contract.counterparty_site) if @contract.counterparty_site
      @party = "counterparty"
    end
  end

  def load_version = @version = @contract.versions.find(params[:version_id])

  def plan_owner?
    owner = Studio::Broadcasting::NetworkCarriage.hub?(@site) ? LightekPwa::Policy.platform_operator(@site) : @site.tenant
    owner == current_user
  end

  def require_issuer!
    raise ActiveRecord::RecordNotFound unless @party == "issuer"
  end

  def require_station_connection!
    require_site!
    raise ActiveRecord::RecordNotFound unless Studio::Broadcasting::InstallationCarriage.connected?(@site)
  end

  def federation = LightekReservations::Federation::Client.new(@site)
  def hosted_endpoint
    path = "broadcast/agreements/#{Integer(params[:id])}/contract"
    return path unless params[:version_id].present? && params[:document].present?

    "#{path}/versions/#{Integer(params[:version_id])}"
  end

  def offer_terms
    form = params.require(:version).permit(:starts_on, :ends_on, :terms, :delivery_target, :amount, :market, :payable_placement_ids, :due_on, :delivery_mode)
    payment_ids = form[:payable_placement_ids].to_s.split(/[\s,]+/).reject(&:empty?).map { |id| Integer(id, 10) }.uniq
    raise ArgumentError, "Choose up to 100 verified ad payments." if payment_ids.size > 100

    { starts_on: Date.iso8601(form[:starts_on].to_s), ends_on: Date.iso8601(form[:ends_on].to_s), terms: form[:terms].to_s.strip,
      delivery_target: Integer(form[:delivery_target].presence || "0", 10), amount_cents: cents(form[:amount].presence || "0"),
      market: form[:market].to_s.strip.presence, payment_ids: payment_ids,
      due_on: (Date.iso8601(form[:due_on]) if form[:due_on].present?), delivery_mode: form[:delivery_mode].presence || "reviewed" }
  end

  def cents(value)
    raise ArgumentError, "Enter a USD amount with up to two decimal places." unless value.to_s.match?(/\A\d{1,9}(?:\.\d{1,2})?\z/)

    whole, fraction = value.to_s.split(".")
    whole.to_i * 100 + fraction.to_s.ljust(2, "0").to_i
  end

  def renewal_versions(contracts)
    BroadcastContractVersion.where(contract_id: contracts.select(:id), ends_on: Date.current..30.days.from_now.to_date)
      .includes(:contract, :signatures).order(:ends_on, :id).select do |version|
        version.executed? && version.contract.versions.where("number > ?", version.number)
          .none? { |replacement| replacement.executed? && replacement.ends_on >= version.ends_on }
      end
  end

  def back(notice)
    redirect_to dashboard_broadcast_contract_path(@contract, site_id: @site&.id, version_id: @version&.id), notice: notice, status: :see_other
  end
end
