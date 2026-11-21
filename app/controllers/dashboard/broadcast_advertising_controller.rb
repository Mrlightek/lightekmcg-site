# frozen_string_literal: true

class Dashboard::BroadcastAdvertisingController < Dashboard::SettingsHomeController
  include LightekIdentity::SensitiveSession
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :load_site
  before_action :require_sensitive_session!, only: %i[release create_demand update_demand save_stream_profile remove_stream_profile reconcile_provider_statement save_viewing_offer]

  rescue_from LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied, ::Gatekeeper::StudioLivePolicy::Denied do |error|
    render plain: error.message, status: :forbidden
  end
  rescue_from ActiveRecord::RecordInvalid do |error|
    redirect_to dashboard_broadcast_advertising_path(site_id: @site.id), alert: error.record.errors.full_messages.to_sentence, status: :see_other
  end

  rescue_from DymondBank::BroadcastAdvertising::Funding::Unavailable do |error|
    redirect_to dashboard_broadcast_advertising_path(site_id: @site.id), alert: error.message, status: :see_other
  end

  rescue_from Studio::Advertising::Exchange::Unavailable, LightekReservations::Federation::Client::Unavailable do |error|
    redirect_to dashboard_broadcast_advertising_path(site_id: @site.id), alert: error.message, status: :see_other
  end

  rescue_from ArgumentError, LightekVault::Service::AccessDenied do |error|
    redirect_to dashboard_broadcast_advertising_path(site_id: @site.id), alert: error.message, status: :see_other
  end

  def show
    @demand_sources = demand_sources.order(:position, :id)
    @stream_profiles = stream_profiles.includes(:channel).order(:channel_id, :platform)
    @provider_statements = provider_statements.includes(:source).order(ends_on: :desc, id: :desc).limit(100)
    @viewing_offer = Studio::Advertising::ViewingOffer.find_by(site: @site)
    @viewing_products = LightekCommerce::Product.where(site: @site, published: true, product_type: "service", billing_interval: %w[month year]).order(:name)
    if Studio::Advertising::Exchange.connected?(@site)
      begin
        @exchange_catalog = Studio::Advertising::Exchange.catalog(@site)
        @exchange_sales = Studio::Advertising::Exchange.sales(@site)
        @exchange_origin = LightekReservations::Federation::Client.config(@site).fetch("origin").delete_suffix("/")
      rescue Studio::Advertising::Exchange::Unavailable, LightekReservations::Federation::Client::Unavailable
        @exchange_unavailable = true
      end
    end
    @networks = networks.includes(:campaigns).order(:name, :id)
    @memberships = Studio::Advertising::Membership.where(station_site_id: @site.id).includes(:network)
    public_network_ids = Studio::Advertising::Campaign.offered.select(:network_id)
    @available_networks = Studio::Advertising::Network.where(id: public_network_ids).where.not(site_id: @site.id)
      .where.not(id: @memberships.select(:network_id)).order(:name, :id).limit(100)
    @videos = videos.includes(proxy_attachment: :blob).order(id: :desc).limit(100)
      .select { |asset| asset.proxy.attached? && asset.metadata["duration"].to_f.floor >= 2 }
    @channels = Studio::Broadcasting::Channel.where(site_id: @site.id, managed_playout: true).order(:name, :id)
    @station_receipts = Studio::Advertising::Placement.delivered.where(station_site_id: @site.id)
      .includes(:campaign).order(delivered_at: :desc).limit(50)
    @producer_receipts = Studio::Advertising::Placement.delivered.where(station_site_id: @site.id, producer_id: current_user.id)
      .includes(:campaign).order(delivered_at: :desc).limit(50)
    @sold = Studio::Advertising::Placement.where(campaign_id: Studio::Advertising::Campaign.where(network: networks))
    @funding_offers = Studio::Advertising::Payment.where(placement: @sold).includes(placement: [:campaign, :airing])
      .order(id: :desc).limit(50)
    @payouts = personal_payouts.includes(payment: { placement: :campaign }).order(id: :desc).limit(50)
    @network_receipts = @sold.delivered
      .includes(:campaign).order(delivered_at: :desc).limit(50)
  end

  def create_demand
    source = demand_sources.new(params.require(:demand).permit(:name, :position, :enabled, :platform))
    source.configure!(tag: params.dig(:demand, :vast_tag), operator: current_user)
    back("Demand source connected.")
  end

  def update_demand
    source = demand_sources.find(params[:id])
    fields = params.require(:demand).permit(:name, :position, :enabled, :platform, :vast_tag)
    tag = fields.delete(:vast_tag)
    source.assign_attributes(fields)
    tag.present? ? source.configure!(tag: tag, operator: current_user) : source.save!
    back("Demand source updated.")
  end

  def save_stream_profile
    fields = params.require(:profile).permit(:channel_id, :platform, :playback_url)
    profile = stream_profiles.find_or_initialize_by(channel_id: fields[:channel_id], platform: fields[:platform])
    profile.update!(playback_url: fields[:playback_url])
    back("Stitched playback URL saved.")
  end

  def remove_stream_profile
    stream_profiles.find(params[:id]).destroy!
    back("Channel now uses its Lightek feed on this platform.")
  end

  def record_provider_statement
    fields = params.require(:statement).permit(:source_id, :reference, :starts_on, :ends_on, :impressions, :reported_cents)
    source = demand_sources.find(fields.delete(:source_id))
    source.statements.create!(fields)
    back("Provider statement recorded.")
  end

  def reconcile_provider_statement
    fields = params.require(:receipt).permit(:received_cents, :deposit_reference)
    provider_statements.find(params[:id]).reconcile!(received: fields[:received_cents], deposit: fields[:deposit_reference], operator: current_user)
    back("Provider deposit reconciled.")
  end

  def save_viewing_offer
    offer = Studio::Advertising::ViewingOffer.find_or_initialize_by(site: @site)
    offer.update!(product_id: params[:product_id])
    back("Fewer Commercials offer saved.")
  end

  def import_offer
    campaign = Studio::Advertising::Exchange.import!(@site, params[:key])
    campaign.network.memberships.create_or_find_by!(station_site_id: @site.id)
    back("Campaign is available in your channel rundown.")
  end

  def release
    DymondBank::BroadcastAdvertising::Settlement.release!(personal_payouts.find(params[:payout_id]), actor: current_user)
    back("Ad earnings transferred to your payout account.")
  end

  def create_network
    networks.create!(params.require(:network).permit(:name))
    back("Ad network created.")
  end

  def join
    public_network_ids = Studio::Advertising::Campaign.offered.select(:network_id)
    network = Studio::Advertising::Network.where(id: public_network_ids).where.not(site_id: @site.id).find(params[:network_id])
    network.memberships.create_or_find_by!(station_site_id: @site.id)
    back("Joined #{network.name}. Its campaigns are now available in your channel rundown.")
  end

  def leave
    Studio::Advertising::Membership.where(station_site_id: @site.id, network_id: params[:network_id]).delete_all
    back("Ad network left. Previously booked placements are still scheduled.")
  end

  def create_campaign
    network = networks.find(params[:network_id])
    terms = params.require(:campaign).permit(:name, :asset_id, :seconds, :rate_cents, :network_bps, :producer_bps, :platform_bps)
    values = terms.to_h
    %w[network_bps producer_bps platform_bps].each do |field|
      values[field] = scaled_decimal(values[field])
    end
    values["rate_cents"] = scaled_decimal(values["rate_cents"])
    asset = videos.find(values.delete("asset_id"))
    network.campaigns.create!(values.merge(asset: asset, blob_id: asset.proxy.blob&.id))
    back("Campaign saved. Open it for booking when you’re ready to offer it across the network.")
  end

  def update_offer
    campaign = networks.find(params[:network_id]).campaigns.find(params[:campaign_id])
    open = params[:open_for_booking] == "1"
    if open && !campaign.creative_available?
      return redirect_to dashboard_broadcast_advertising_path(site_id: @site.id), alert: "This campaign’s original video is unavailable. Create a campaign using a ready video.", status: :see_other
    end

    if Studio::Advertising::Exchange.connected?(@site)
      Studio::Advertising::Exchange.publish!(@site, campaign, open: open)
    else
      campaign.update!(open_for_booking: open)
    end
    back(open ? "Campaign open for booking." : "Campaign closed to new bookings. Existing bookings are still scheduled.")
  end

  private

  def load_site
    response.set_header("Cache-Control", "private, no-store")
    ::Gatekeeper::StudioLivePolicy.authorize!(user: current_user)
    @site = Studio::Broadcasting::Access.site(user: current_user, host: request.host, id: params[:site_id])
    raise ActiveRecord::RecordNotFound unless @site

    Studio::Broadcasting::Access.authorize!(current_user, @site)
  end

  def demand_sources = Studio::Advertising::DemandSource.where(site: @site)
  def stream_profiles = Studio::Advertising::StreamProfile.where(site: @site)
  def provider_statements = Studio::Advertising::ProviderStatement.where(source_id: demand_sources.select(:id))

  def networks
    Studio::Advertising::Network.where(site_id: @site.id, imported: false)
  end

  def personal_payouts
    Studio::Advertising::Payout.where(recipient: current_user)
  end

  def videos
    actor = Studio::PwaAccess.new("user_id" => current_user.id, "site_id" => @site.id)
    StudioAsset.for_actor(actor).where(site_id: @site.id, kind: "video", status: "ready")
  end

  def scaled_decimal(input)
    text = input.to_s
    return unless text.match?(/\A[0-9]{1,5}(?:\.[0-9]{1,2})?\z/)

    whole, fraction = text.split(".")
    whole.to_i * 100 + fraction.to_s.ljust(2, "0").to_i
  end

  def back(notice)
    redirect_to dashboard_broadcast_advertising_path(site_id: @site.id), notice: notice, status: :see_other
  end
end
