# frozen_string_literal: true
class ReservationsController < ApplicationController
  skip_authorization_check
  protect_from_forgery with: :exception
  layout 'reservations'
  allow_unauthenticated_access only: %i[catalog slots]
  before_action :resume_session, only: %i[catalog slots]
  before_action { response.headers['Cache-Control'] = 'no-store, private' }
  rescue_from LightekReservations::Availability::Invalid, LightekReservations::Booking::Invalid,
    LightekReservations::PackageChanges::Invalid, LightekCommerce::OrderPlacement::Invalid,
    LightekCommerce::InstallationCheckout::Invalid, LightekCommerce::StripeCheckout::Unavailable,
    ActiveRecord::RecordInvalid, LightekReservations::Federation::Client::Unavailable, with: :booking_error

  def catalog
    @site = public_site
    @resources = @site ? LightekReservations::Resource.available.where(site: @site).includes(:product) : LightekReservations::Resource.none
    @network = nil
    if LightekReservations::Federation::Client.config(@site)
      begin
        @network = LightekReservations::Federation::Client.new(@site).request('catalog')
      rescue LightekReservations::Federation::Client::Unavailable => error
        flash.now[:alert] = error.message
      end
    end
    @industry = params[:industry].to_s
    @resources = @resources.where(template_key: @industry) if @industry.present?
  end
  def slots
    resource = LightekReservations::Resource.available.where(site: public_site).find(params.require(:resource_id))
    render json: {timezone: resource.timezone, slots: LightekReservations::Availability.slots(resource: resource, date: params.require(:date))}
  end
  def index
    @reservations = LightekReservations::Reservation.where(customer: current_user).includes(resource: :site).order(starts_at: :desc).limit(100)
    site = DymondSite::Site.find_by(host: request.host)
    @network_reservations = []
    if LightekReservations::Federation::Client.config(site)
      begin
        @network_reservations = LightekReservations::Federation::Client.new(site).request("reservations/#{current_user.id}").fetch('reservations')
      rescue LightekReservations::Federation::Client::Unavailable => error
        flash.now[:alert] = error.message
      end
    end
    @central_reservation = site&.manifest.to_h&.fetch('lightek_reservation', nil)
  end
  def show
    @reservation = customer_reservation
    LightekReservations::Booking.reconcile!(@reservation)
    @resource = @reservation.resource
    @alternatives = LightekReservations::Resource.available.where(site_id: @resource.site_id, kind: 'server').includes(:product)
    @changes = @reservation.package_changes.order(created_at: :desc)
  end
  def create
    if params[:network_offer_id].present?
      site = public_site
      client = LightekReservations::Federation::Client.new(site)
      url = client.checkout(checkout: {offer_id: params.require(:network_offer_id), starts_at: params.require(:starts_at),
        checkout_key: params.require(:checkout_key), subject: current_user.id.to_s})
      return redirect_to url, allow_other_host: true, status: :see_other
    end
    resource = LightekReservations::Resource.available.where(site: public_site).find(params.require(:resource_id))
    reservation = LightekReservations::Booking.reserve!(customer: current_user, resource: resource,
      starts_at: params.require(:starts_at), checkout_key: params.require(:checkout_key),
      quantity: params.fetch(:quantity, 1), notes: params[:notes])
    redirect_to my_reservation_path(reservation), status: :see_other
  end
  def checkout
    reservation = customer_reservation
    raise LightekReservations::Booking::Invalid, 'This reservation is not awaiting payment' unless reservation.status == 'held' && reservation.order&.status == 'pending_payment'
    session = LightekCommerce::StripeCheckout.start!(order: reservation.order,
      success_url: my_reservation_url(reservation), cancel_url: my_reservation_url(reservation))
    redirect_to session.url, allow_other_host: true, status: :see_other
  end
  def cancel
    reservation = customer_reservation
    LightekReservations::Booking.cancel!(reservation: reservation, actor: current_user)
    redirect_to my_reservation_path(reservation), notice: 'Reservation canceled. Any paid refund is handled separately by the provider.'
  end
  def reschedule
    reservation = customer_reservation
    LightekReservations::Booking.reschedule!(reservation: reservation, actor: current_user, starts_at: params.require(:starts_at))
    redirect_to my_reservation_path(reservation), notice: 'Your appointment has been rescheduled.'
  end
  def quote
    reservation = customer_reservation
    target = LightekReservations::Resource.available.where(site_id: reservation.resource.site_id).find(params.require(:target_resource_id))
    LightekReservations::PackageChanges.quote!(reservation: reservation, target: target)
    redirect_to my_reservation_path(reservation), notice: 'Your package quote is ready to review.'
  end
  def accept_change
    reservation = customer_reservation
    change = reservation.package_changes.find(params.require(:change_id))
    LightekReservations::PackageChanges.accept!(change: change, actor: current_user)
    if change.order&.status == 'pending_payment'
      session = LightekCommerce::StripeCheckout.start!(order: change.order,
        success_url: my_reservation_url(reservation), cancel_url: my_reservation_url(reservation))
      redirect_to session.url, allow_other_host: true, status: :see_other
    else
      redirect_to my_reservation_path(reservation), notice: 'Your package change is scheduled.'
    end
  end
  def calendar
    reservation = customer_reservation
    escape = ->(text) { text.to_s.gsub('\\', '\\\\').gsub(/\r?\n/, '\\n').gsub(',', '\\,').gsub(';', '\\;') }
    body = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Lightek//Reservations//EN', 'BEGIN:VEVENT',
      "UID:#{reservation.reference}@lightek", "DTSTAMP:#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}",
      "DTSTART:#{reservation.starts_at.utc.strftime('%Y%m%dT%H%M%SZ')}", "DTEND:#{reservation.ends_at.utc.strftime('%Y%m%dT%H%M%SZ')}",
      "SUMMARY:#{escape.call(reservation.package_snapshot['name'])}", "LOCATION:#{escape.call(reservation.resource.location)}",
      "STATUS:#{%w[canceled expired].include?(reservation.status) ? 'CANCELLED' : 'CONFIRMED'}", 'END:VEVENT', 'END:VCALENDAR'].join("\r\n")
    send_data body, type: 'text/calendar; charset=utf-8', disposition: 'attachment', filename: "#{reservation.reference}.ics"
  end
  private
  def customer_reservation
    LightekReservations::Reservation.where(customer: current_user).find(params.require(:id))
  end
  def public_site
    # Public booking stays on the requested white-label hostname. Owners may
    # preview their own catalog from the main dashboard with an explicit site.
    host_site = DymondSite::Site.find_by(host: request.host)
    return host_site if params[:site_id].blank? || host_site&.id.to_s == params[:site_id].to_s
    LightekSettings::WebsiteIdentity.sites_for(current_user).find(params[:site_id])
  end
  def booking_error(error)
    redirect_to(params[:id].present? ? my_reservation_path(params[:id]) : reservations_catalog_path,
      alert: error.message, status: :see_other)
  end
end
