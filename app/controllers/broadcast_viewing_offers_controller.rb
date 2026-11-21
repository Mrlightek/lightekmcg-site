# frozen_string_literal: true

class BroadcastViewingOffersController < ApplicationController
  def checkout
    site = LightekPwa::SiteContext.resolve(request.host)
    offer = Studio::Advertising::ViewingOffer.find_by!(site: site)
    raise ActiveRecord::RecordNotFound unless offer.valid?
    raise ActiveRecord::RecordNotFound unless Studio::Advertising::StreamProfile.exists?(site: site)
    order = current_user.with_lock do
      raise ArgumentError, "Fewer Commercials is already active." if Studio::Advertising::ViewingOffer.active?(site, current_user)

      prior = LightekCommerce::Order.where(site: site, hosting_owner: current_user, purpose: "fewer_commercials", status: "pending_payment")
        .joins(:items).where(lightek_commerce_order_items: { product_id: offer.product_id })
        .where("lightek_commerce_orders.created_at > ?", 30.minutes.ago).order(id: :desc).first
      prior || LightekCommerce::OrderPlacement.call(site: site, customer_email: current_user.email_address,
        buyer: current_user, quantities: { offer.product_id.to_s => 1 }).tap do |purchase|
        purchase.update!(hosting_owner: current_user, purpose: "fewer_commercials")
      end
    end
    payment = LightekCommerce::StripeCheckout.start!(order: order, success_url: broadcast_tv_url, cancel_url: broadcast_tv_url)
    redirect_to payment.url, allow_other_host: true, status: :see_other
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue ArgumentError, LightekCommerce::OrderPlacement::Invalid, LightekCommerce::StripeCheckout::Unavailable => error
    redirect_to broadcast_tv_path, alert: error.message, status: :see_other
  end
end
