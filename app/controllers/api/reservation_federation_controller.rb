class Api::ReservationFederationController < ActionController::Base
  skip_forgery_protection
  before_action :authenticate_peer
  rescue_from ActiveRecord::RecordNotFound, with: -> { render json: {error: 'Reservation resource not found'}, status: :not_found }
  rescue_from ActiveRecord::RecordInvalid, ArgumentError, KeyError, LightekReservations::Availability::Invalid,
    LightekReservations::Booking::Invalid, LightekAgency::PackagePolicy::Denied, with: ->(e) { render json: {error: e.message}, status: :unprocessable_entity }
  def catalog
    authorize_reselling!
    render json: {approved: LightekAgency::HostingCatalog.rows,
      offers: catalog_service.offers(@peer).map { |r| catalog_service.serialize(r) },
      templates: LightekDesign::StarterLibrary.designs.map { |key, value| {key: key, name: value['name'], industry: value['industry']} },
      merchant_url: "#{LightekReservations::Federation::Issuer.origin}/my/resort-earnings?peer=#{@peer.key}"}
  end
  def save_offer
    authorize_reselling!
    attributes = params.require(:offer).permit(:id, :name, :description, :source_id, :price_cents, :template_key, :published, package_policy: {}).to_h
    @peer.site.update!(name: params[:brand_name].to_s.first(160)) if params[:brand_name].present?
    resource = catalog_service.save!(peer: @peer, attributes: attributes)
    render json: {offer: catalog_service.serialize(resource)}
  end
  def intent
    attributes = params.require(:checkout).permit(:offer_id, :starts_at, :checkout_key, :subject).to_h
    intent = catalog_service.create_intent!(peer: @peer, attributes: attributes)
    render json: {url: "#{LightekReservations::Federation::Issuer.origin}/network/reservations/#{intent.token}"}
  end
  def reservations
    intents = @peer.intents.where(remote_subject: params.require(:subject)).where.not(reservation_id: nil).includes(reservation: :resource).order(created_at: :desc).limit(100)
    render json: {reservations: intents.map { |intent|
      reservation = intent.reservation
      {reference: reservation.reference, name: reservation.package_snapshot['name'], status: reservation.status,
        starts_at: reservation.starts_at.iso8601, ends_at: reservation.ends_at.iso8601,
        url: "#{LightekReservations::Federation::Issuer.origin}/my/reservations/#{reservation.id}"}
    }}
  end
  def payouts
    merchant = @peer.merchant
    if params[:merchant_chain]
      values = params.permit(:store_name, merchant_chain: %i[subject email first_name last_name role upstream_share_bps]).to_h
      merchant, = LightekCommerce::NetworkAccounts.resolve!(peer: @peer, chain: values.fetch('merchant_chain'), store_name: values.fetch('store_name'))
    end
    state = LightekPayments::PayoutAccounts.status(merchant)
    schedule = LightekCommerce::PayoutSchedule.for!(merchant)
    if request.patch?
      cadence = params.require(:cadence)
      raise ArgumentError, 'Choose weekly or biweekly' unless %w[weekly biweekly].include?(cadence)
      schedule.with_lock do
        schedule.update!(cadence: cadence, enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]),
          next_run_at: Time.current + (cadence == 'weekly' ? 7 : 14).days)
      end
    end
    render json: {cadence: schedule.cadence, enabled: schedule.enabled?, next_run_at: schedule.next_run_at.iso8601,
      connect_ready: state[:state] == 'ready', connect_account_id: merchant.stripe_connect_account_id,
      connect_details_submitted: merchant.stripe_connect_details_submitted?, connect_payouts_enabled: state[:state] == 'ready', last_error: nil,
      merchant_url: "#{LightekReservations::Federation::Issuer.origin}/my/resort-earnings?peer=#{@peer.key}"}
  end
  private
  def authorize_reselling!
    data = @peer.order&.items&.first&.purchase_snapshot.to_h['managed_package'] if @peer.respond_to?(:order)
    if data && !LightekAgency::PackagePolicy.normalize(data.fetch('policy'))['features']['agency']['enabled']
      raise LightekAgency::PackagePolicy::Denied, 'This installation package does not include reseller tools.'
    end
  end
  def catalog_service = LightekReservations::Federation::Catalog
  def authenticate_peer
    response.headers['Cache-Control'] = 'no-store'
    return head :upgrade_required if Rails.env.production? && !request.ssl?
    @peer = LightekReservations::Peer.authenticate(request.authorization.to_s.delete_prefix('Bearer '))
    return head :unauthorized unless @peer
    if @peer.respond_to?(:pwa_only?) && @peer.pwa_only? && !%w[Api::PwaPublicationsController Api::PwaYoutubeFederationController Api::PwaMemberSessionsController].include?(self.class.name)
      return head :forbidden
    end
  end
end
