class Api::ReservationFederationController < ActionController::Base
  skip_forgery_protection
  before_action :authenticate_peer
  rescue_from ActiveRecord::RecordNotFound, with: -> { render json: {error: 'Reservation resource not found'}, status: :not_found }
  rescue_from ActiveRecord::RecordInvalid, ArgumentError, KeyError, LightekReservations::Availability::Invalid,
    LightekReservations::Booking::Invalid, with: ->(e) { render json: {error: e.message}, status: :unprocessable_entity }
  def catalog
    render json: {approved: catalog_service.approved.map { |r| catalog_service.serialize(r) },
      offers: catalog_service.offers(@peer).map { |r| catalog_service.serialize(r) },
      templates: LightekDesign::StarterLibrary.designs.map { |key, value| {key: key, name: value['name'], industry: value['industry']} },
      merchant_url: "#{LightekReservations::Federation::Issuer.origin}/my/resort-earnings?peer=#{@peer.key}"}
  end
  def save_offer
    attributes = params.require(:offer).permit(:id, :name, :description, :source_id, :price_cents, :template_key, :published).to_h
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
    schedule = LightekCommerce::PayoutSchedule.for!(@peer.merchant)
    if request.patch?
      cadence = params.require(:cadence)
      raise ArgumentError, 'Choose weekly or biweekly' unless %w[weekly biweekly].include?(cadence)
      schedule.with_lock do
        schedule.update!(cadence: cadence, enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]),
          next_run_at: Time.current + (cadence == 'weekly' ? 7 : 14).days)
      end
    end
    render json: {cadence: schedule.cadence, enabled: schedule.enabled?, next_run_at: schedule.next_run_at.iso8601,
      connect_ready: @peer.merchant.stripe_connect_ready?, connect_account_id: @peer.merchant.stripe_connect_account_id,
      connect_details_submitted: @peer.merchant.stripe_connect_details_submitted, connect_payouts_enabled: @peer.merchant.stripe_connect_payouts_enabled, last_error: schedule.last_error,
      merchant_url: "#{LightekReservations::Federation::Issuer.origin}/my/resort-earnings?peer=#{@peer.key}"}
  end
  private
  def catalog_service = LightekReservations::Federation::Catalog
  def authenticate_peer
    response.headers['Cache-Control'] = 'no-store'
    return head :upgrade_required if Rails.env.production? && !request.ssl?
    @peer = LightekReservations::Peer.authenticate(request.authorization.to_s.delete_prefix('Bearer '))
    head :unauthorized unless @peer
  end
end
