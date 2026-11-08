class NetworkReservationsController < ApplicationController
  skip_authorization_check
  protect_from_forgery with: :exception
  layout 'reservations'
  before_action { response.headers['Cache-Control'] = 'no-store, private' }
  rescue_from ArgumentError, LightekReservations::Availability::Invalid, LightekReservations::Booking::Invalid,
    ActiveRecord::RecordInvalid, LightekCommerce::OrderPlacement::Invalid, with: :checkout_error
  def show
    @intent = intent
    return redirect_to my_reservation_path(@intent.reservation) if @intent.reservation && @intent.customer_id == current_user.id
    raise ActiveRecord::RecordNotFound if @intent.customer_id && @intent.customer_id != current_user.id
    raise ArgumentError, 'This checkout has expired' if @intent.expires_at <= Time.current
    @resource = @intent.resource
    @site = @intent.peer.site
  end
  def book
    reservation = LightekReservations::Federation::Catalog.book!(intent: intent, customer: current_user)
    redirect_to my_reservation_path(reservation), status: :see_other
  end
  def earnings
    @peer = LightekReservations::Peer.where(merchant: current_user).find_by!(key: params.require(:peer))
    @site = @peer.site
    @payout_schedule = LightekCommerce::PayoutSchedule.for!(current_user)
    @orders = LightekCommerce::Order.where(site: @site, status: 'fulfilled').includes(:refunds).order(created_at: :desc).limit(100)
  end
  def schedule
    peer = LightekReservations::Peer.where(merchant: current_user).find_by!(key: params.require(:peer))
    cadence = params.require(:cadence)
    raise ArgumentError, 'Choose weekly or biweekly' unless %w[weekly biweekly].include?(cadence)
    schedule = LightekCommerce::PayoutSchedule.for!(current_user)
    schedule.with_lock { schedule.update!(cadence: cadence, enabled: params[:enabled] == '1', next_run_at: Time.current + (cadence == 'weekly' ? 7 : 14).days) }
    redirect_to resort_earnings_path(peer: peer.key), notice: 'Payout schedule saved.'
  end
  private
  def intent
    LightekReservations::Intent.joins(:peer).where(lightek_reservation_peers: {enabled: true}).find_by!(token: params.require(:token))
  end
  def checkout_error(error)
    redirect_to my_reservations_path, alert: error.message
  end
end
