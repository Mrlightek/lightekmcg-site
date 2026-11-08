# frozen_string_literal: true
class Dashboard::ReservationsController < Dashboard::SettingsHomeController
  layout 'dymond_dash/layouts/dymond_dash'
  protect_from_forgery with: :exception
  before_action :load_site
  rescue_from ActiveRecord::RecordInvalid, LightekReservations::Booking::Invalid,
    LightekReservations::Availability::Invalid, JSON::ParserError, ArgumentError, with: :invalid_booking
  def network
    @network = network_client.request('catalog')
    @network_payouts = network_client.request('payouts')
    render 'dashboard/reservations/network'
  rescue LightekReservations::Federation::Client::Unavailable => error
    redirect_to dashboard_reservations_path(site_id: @site.id), alert: error.message
  end
  def network_offer
    values = params.require(:offer).permit(:id, :name, :description, :source_id, :price_cents, :template_key, :published).to_h
    network_client.request('offers', body: {offer: values, brand_name: @site.name}, method: :post)
    redirect_to network_dashboard_reservations_path(site_id: @site.id), notice: 'Server resort offer saved on the Lightek network.'
  rescue LightekReservations::Federation::Client::Unavailable => error
    redirect_to network_dashboard_reservations_path(site_id: @site.id), alert: error.message
  end
  def network_payouts
    network_client.request('payouts', method: :patch, body: {cadence: params.require(:cadence), enabled: params[:enabled] == '1'})
    redirect_to network_dashboard_reservations_path(site_id: @site.id), notice: 'Your central payout schedule has been updated.'
  rescue LightekReservations::Federation::Client::Unavailable => error
    redirect_to network_dashboard_reservations_path(site_id: @site.id), alert: error.message
  end
  def index
    @resources = LightekReservations::Resource.where(site: @site).includes(:product).order(:name)
    @resource = params[:resource_id].present? ? @resources.find(params[:resource_id]) : LightekReservations::Resource.new(site: @site)
    @server_packages = LightekReservations::Resource.available.where(kind: 'server', source_resource_id: nil).where(site_id: DymondSite::Site.where(tenant: User.where(role: 'super_admin')).select(:id))
    @products = LightekCommerce::Product.where(site: @site, product_type: %w[digital lightek_instance]).order(:name)
    @reservations = LightekReservations::Reservation.joins(:resource).where(lightek_reservation_resources: {site_id: @site.id})
    @metrics = {upcoming: @reservations.where(status: %w[confirmed checked_in]).where('starts_at >= ?', Time.current).count,
      held: @reservations.where(status: 'held').count, resources: @resources.count,
      booked: @reservations.where(status: %w[confirmed checked_in completed]).count}
    @day = params[:date].present? ? Date.iso8601(params[:date]) : Date.current
    @reservations = @reservations.where('starts_at < ? AND ends_at > ?', @day.end_of_day, @day.beginning_of_day).includes(:customer, :resource, :order).order(:starts_at)
    @changes = LightekReservations::Change.joins(reservation: :resource).where(lightek_reservation_resources: {site_id: @site.id}).includes(:reservation, :target_resource).order(created_at: :desc).limit(25)
    @blackouts = LightekReservations::Blackout.where(resource_id: @resources.select(:id)).order(starts_at: :desc).limit(20)
  end
  def save_resource
    resource = params[:id].present? ? LightekReservations::Resource.where(site: @site).find(params[:id]) : LightekReservations::Resource.new(site: @site)
    attributes = params.require(:resource).permit(:name, :description, :kind, :timezone, :capacity, :duration_minutes,
      :buffer_minutes, :notice_minutes, :cancellation_hours, :published, :product_id, :location, :join_url, :template_key,
      :billing_interval, :cost_floor_cents, :accommodations_text, compute: %i[region plan image monthly_cost_cents], opening_hours: Date::DAYNAMES.each_index.to_h { |i| [i.to_s, %i[open close]] }).to_h
    attributes['hours'] = attributes.delete('opening_hours').to_h.filter_map do |day, window|
      next if window['open'].blank? && window['close'].blank?
      [day, [[window['open'], window['close']]]]
    end.to_h
    attributes['compute'] ||= {}
    if attributes['compute']['monthly_cost_cents'].present?
      attributes['compute']['monthly_cost_cents'] = Integer(attributes['compute']['monthly_cost_cents'])
    end
    attributes['accommodations'] = attributes.delete('accommodations_text').to_s.lines.map(&:strip).reject(&:blank?)
    if current_user.role != 'super_admin' && attributes['kind'] == 'server'
      source = LightekReservations::Resource.available.where(kind: 'server', source_resource_id: nil).find(params.require(:approved_server_id))
      raise ArgumentError, 'Choose a platform-approved server package' unless source.site.tenant&.role == 'super_admin'
      attributes.merge!('source_resource_id' => source.id, 'compute' => source.compute,
        'cost_floor_cents' => source.cost_floor_cents, 'billing_interval' => source.billing_interval)
    end
    resource.assign_attributes(attributes)
    resource.product_id = nil if resource.product_id.blank?
    resource.save!
    redirect_to dashboard_reservations_path(site_id: @site.id, resource_id: resource.id), notice: 'Experience saved.'
  end
  def retry_change
    change = LightekReservations::Change.joins(reservation: :resource).where(lightek_reservation_resources: {site_id: @site.id}).find(params.require(:id))
    change.with_lock do
      raise ArgumentError, 'Only a failed, verified paid package change can resume' unless change.status == 'failed' && change.order&.paid_at? && %w[paid fulfilled].include?(change.order.status)
      change.update!(status: 'scheduled', error: nil, provider_receipt: {})
    end
    LightekReservations::PackageChangeJob.perform_later(change.id)
    redirect_to dashboard_reservations_path(site_id: @site.id), notice: 'The paid package change is queued to resume.'
  end
  def create_booking
    resource = LightekReservations::Resource.available.where(site: @site).find(params.require(:resource_id))
    customer = User.find_by(email_address: params.require(:customer_email).to_s.strip.downcase)
    raise ArgumentError, 'Ask the guest to create an account before booking on their behalf' unless customer
    booking = LightekReservations::Booking.reserve!(customer: customer, resource: resource,
      starts_at: params.require(:starts_at), checkout_key: params.require(:checkout_key),
      quantity: params.fetch(:quantity, 1), notes: params[:notes])
    redirect_to dashboard_reservations_path(site_id: @site.id), notice: "Reservation #{booking.reference} created. The guest can complete payment from My reservations."
  end
  def blackout
    resource = LightekReservations::Resource.where(site: @site).find(params.require(:resource_id))
    resource.with_lock do
      start = LightekReservations::Availability.parse(params.require(:starts_at), resource)
      finish = LightekReservations::Availability.parse(params.require(:ends_at), resource)
      raise ArgumentError, 'Move existing reservations before blocking this time' if resource.reservations.occupying.where('blocks_from < ? AND blocks_until > ?', finish, start).exists?
      resource.blackouts.create!(starts_at: start, ends_at: finish, reason: params[:reason])
    end
    redirect_to dashboard_reservations_path(site_id: @site.id), notice: 'Unavailable time blocked.'
  end
  def remove_blackout
    resource_ids = LightekReservations::Resource.where(site: @site).select(:id)
    LightekReservations::Blackout.where(resource_id: resource_ids).find(params.require(:id)).destroy!
    redirect_to dashboard_reservations_path(site_id: @site.id), notice: 'Blocked time removed.'
  end
  def transition
    reservation = LightekReservations::Reservation.joins(:resource).where(lightek_reservation_resources: {site_id: @site.id}).find(params.require(:id))
    if params[:status] == 'canceled'
      LightekReservations::Booking.cancel!(reservation: reservation, actor: current_user)
    else
      reservation.with_lock do
        valid = {'confirmed' => ['checked_in'], 'checked_in' => ['completed']}
        raise ArgumentError, 'Invalid reservation transition' unless valid.fetch(reservation.status, []).include?(params[:status])
        raise ArgumentError, 'Server activation is confirmed by the provisioning pipeline' if reservation.server?
        raise ArgumentError, 'Payment must be verified before check-in' unless reservation.access_ready?
        reservation.update!(status: params[:status])
        LightekCommerce::Fulfillment.complete!(order: reservation.order, reference: reservation.reference) if reservation.status == 'completed' && reservation.order&.status == 'paid'
      end
    end
    redirect_to dashboard_reservations_path(site_id: @site.id), notice: 'Reservation updated.'
  end
  private
  def network_client = LightekReservations::Federation::Client.new(@site)
  def load_site
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.order(:id).first
    render plain: 'Create a website before adding reservation experiences.', status: :unprocessable_entity unless @site
  end
  def invalid_booking(error)
    redirect_to dashboard_reservations_path(site_id: @site.id), alert: error.message
  end
end
