# frozen_string_literal: true
class CommerceController < ApplicationController
  allow_unauthenticated_access only: %i[index add remove]
  helper LightekDesign::StudioHelper
  helper DymondDash::TemplateSchemaHelper
  skip_authorization_check
  before_action :set_site
  def index
    if params[:order_id].present?
      order = LightekCommerce::Order.where(site: @site).find_by(id: params[:order_id])
      LightekCommerce::NetworkCheckout.synchronize!(order) if order&.payment_provider == "network"
    end
    @products = LightekCommerce::Product.visible.where(site: @site)
    @cart = cart
    keys = Array(session["lightek_shipping_quotes_#{@site.id}"]).first(10)
    @shipping_quotes = LightekShipping::Quote.where(site: @site, public_key: keys).where("expires_at > ?", Time.current)
      .where(cart_fingerprint: LightekShipping::Quotes.fingerprint(@site, @cart))
    page_id = @site.manifest.to_h["lightek_commerce_starter_page_id"]
    @page = @site.pages.find_by(id: page_id, published: true) if page_id
    design_key = @site.manifest.to_h["lightek_commerce_design_key"]
    unless @page
      candidates = @site.manifest.to_h.fetch("lightek_commerce_design_pages", {})
      @page = @site.pages.where(id: candidates.keys, published: true).order(created_at: :desc).first
      design_key = candidates[@page.id.to_s] if @page
    end
    if @page && design_key.present?
      @design_key = design_key
      render "commerce/styled", layout: "lightek_design/website"
    end
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
    quote = LightekShipping::Quote.where(site: @site).find_by!(public_key: params[:shipping_quote_key]) if params[:shipping_quote_key].present?
    physical = LightekCommerce::Product.where(site: @site, id: cart.keys.map { |key| key.split(":").first }, product_type: "physical").exists?
    if physical && LightekShipping::Profile.exists?(site: @site) && !quote
      raise LightekCommerce::OrderPlacement::Invalid, "Choose a shipping quote before payment"
    end
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: email, quantities: cart, shipping_quote: quote)
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
