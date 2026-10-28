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
    current = cart.fetch(product.id.to_s, 0).to_i
    raise ArgumentError if current + quantity > 100
    cart[product.id.to_s] = current + quantity
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
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: params.require(:customer_email), quantities: cart)
    session.delete(cart_key)
    redirect_to commerce_shop_path(site_id: @site.id), notice: "Order ##{order.id} reserved. Payment is not yet available; your order is pending payment."
  rescue LightekCommerce::OrderPlacement::Invalid, ActiveRecord::RecordInvalid => e
    redirect_to commerce_shop_path(site_id: @site.id), alert: e.message
  end
  private
  def set_site
    @site = DymondSite::Site.find(params.require(:site_id))
  end
  def cart_key
    "lightek_commerce_cart_#{@site.id}"
  end
  def cart
    @cart ||= session[cart_key].to_h
  end
end
