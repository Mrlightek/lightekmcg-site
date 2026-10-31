# frozen_string_literal: true
class CommerceController < ApplicationController
  allow_unauthenticated_access only: %i[index add remove]
  skip_authorization_check
  before_action :set_site
  def index
    @products = LightekCommerce::Product.visible.where(site: @site)
    @cart = cart
  end
  def add
    product = LightekCommerce::Product.visible.where(site: @site).find(params[:product_id])
    quantity = Integer(params.fetch(:quantity, 1))
    raise ArgumentError unless quantity.between?(1, 100)
    variant_id = params[:variant_id].presence
    if variant_id
      variant = product.variants.where(active: true).find(variant_id)
    elsif product.variants.where(active: true).exists?
      raise ArgumentError, "Select a product option"
    end
    key = variant_id ? "#{product.id}:#{variant.id}" : product.id.to_s
    current = cart.fetch(key, 0).to_i
    raise ArgumentError if current + quantity > 100
    cart[key] = current + quantity
    session[cart_key] = cart
    redirect_to commerce_shop_path(site_id: @site.id), notice: "Added to cart."
  rescue ArgumentError, TypeError
    redirect_to commerce_shop_path(site_id: @site.id), alert: "Enter a valid quantity."
  end
  def remove
    cart.delete(params[:product_id].to_s)
    session[cart_key] = cart
    redirect_to commerce_shop_path(site_id: @site.id), notice: "Cart updated."
  end
  def checkout
    instance_cart = LightekCommerce::Product.where(site: @site, id: cart.keys.map { |key| key.split(":").first }, product_type: "lightek_instance").exists?
    email = instance_cart ? current_user.email_address : params.require(:customer_email)
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: email, quantities: cart)
    checkout = LightekCommerce::StripeCheckout.start!(order: order,
      success_url: instance_cart ? installation_url(order) : commerce_shop_url(site_id: @site.id, order_id: order.id),
      cancel_url: commerce_shop_url(site_id: @site.id))
    session.delete(cart_key)
    redirect_to checkout.url, allow_other_host: true
  rescue LightekCommerce::OrderPlacement::Invalid, LightekCommerce::StripeCheckout::Unavailable, ActiveRecord::RecordInvalid => e
    # A session was never handed to the customer; release the reserved stock.
    LightekCommerce::OrderPlacement.cancel!(order) if order&.persisted? && order.reload.payment_reference.blank? && order.status == "pending_payment"
    redirect_to commerce_shop_path(site_id: @site.id), alert: e.message
  end
  private
  def set_site
    @site = DymondSite::Site.find(params.require(:site_id))
  end
  def cart_key = "lightek_commerce_cart_#{@site.id}"
  def cart = @cart ||= session[cart_key].to_h
end
