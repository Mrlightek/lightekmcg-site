# frozen_string_literal: true

class BroadcastAdPaymentsController < ApplicationController
  allow_unauthenticated_access
  protect_from_forgery with: :exception
  before_action :load_payment

  def show
  end

  def create
    return_url = "#{LightekReservations::Federation::Issuer.origin}#{broadcast_ad_payment_path(@payment.public_key)}"
    destination = DymondBank::BroadcastAdvertising::Funding.checkout!(@payment, return_url: return_url)
    redirect_to destination, allow_other_host: true, status: :see_other
  rescue DymondBank::BroadcastAdvertising::Funding::Unavailable => error
    redirect_to broadcast_ad_payment_path(@payment.public_key), alert: error.message, status: :see_other
  end

  private

  def load_payment
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex")
    @payment = Studio::Advertising::Payment.find_by!(public_key: params[:key])
  end
end
