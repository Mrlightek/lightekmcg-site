# frozen_string_literal: true
class CommerceController < ApplicationController
  allow_unauthenticated_access only: %i[index add remove]
  helper LightekDesign::StudioHelper
  helper DymondDash::TemplateSchemaHelper
  skip_authorization_check
  before_action :set_site
  layout 'auth', only: :embedded_checkout
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
    elsif LightekDesign::Catalog.active?(@site)
      @page = Struct.new(:title,:theme,:sections).new("Shop",nil,[])
      render "commerce/index", layout: "lightek_design/website"
    end
  end
  def add
    product = LightekCommerce::Product.visible.where(site: @site).find(params[:product_id])
    if product.full_communications_package?
      return redirect_to full_package_installations_path(product_id: product.id), status: :see_other
    end

    quantity = Integer(params.fetch(:quantity, 1).to_s, 10)
    seat_range = Gatekeeper::Hosting::WorkspacePlans.seats_for(product)
    return select_workspace(product, quantity, seat_range) if seat_range

    raise ArgumentError unless quantity.between?(1, 100)

    if workspace_in_cart
      return redirect_to commerce_shop_path(site_id: @site.id), alert: "Check out your Workspace plan separately."
    end

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
    quantities, workspace_seats = checkout_selection
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: email, quantities: quantities,
      workspace_seats: workspace_seats, shipping_quote: quote,
      growth_visit: LightekGrowth::Tracking.from_request(site: @site, cookies: cookies, request: request))
    embedded = ENV['LIGHTEK_COMMERCE_EMBEDDED_CHECKOUT'] == 'true' && LightekCommerce::StripeCheckout.embedded_for?(order)
    checkout = LightekCommerce::StripeCheckout.start!(order: order,
      success_url: completion_url(order, instance_cart), cancel_url: commerce_shop_url(site_id: @site.id), embedded: embedded)
    record_platform_experiment('checkout', order) if respond_to?(:record_platform_experiment, true)
    session.delete(cart_key)
    if embedded
      recent = session[:embedded_store_orders].to_h
      recent[order.id.to_s] = [@site.id, current_user.id, request.host, instance_cart]
      session[:embedded_store_orders] = recent.to_a.last(5).to_h
      redirect_to commerce_embedded_checkout_path(site_id: @site.id, order_id: order.id), status: :see_other
    else
      redirect_to checkout.url, allow_other_host: true
    end
  rescue LightekCommerce::OrderPlacement::Invalid, LightekCommerce::StripeCheckout::Unavailable, ActiveRecord::RecordInvalid => e
    # A session was never handed to the customer; release the reserved stock.
    LightekCommerce::OrderPlacement.cancel!(order) if order&.persisted? && order.reload.payment_reference.blank? && order.status == "pending_payment"
    redirect_to commerce_shop_path(site_id: @site.id), alert: e.message
  end
  def embedded_checkout
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
    context = session[:embedded_store_orders].to_h[params[:order_id].to_s]
    unless context && context.first(3) == [@site.id, current_user.id, request.host]
      raise ActiveRecord::RecordNotFound
    end

    order = LightekCommerce::Order.visible.where(site: @site).find(params[:order_id])
    @completion_url = completion_url(order, context.last)
    return redirect_to @completion_url if order.paid_at?

    @checkout = LightekCommerce::StripeCheckout.resume!(order: order, embedded: true)
    @publishable_key = LightekCommerce::StripeCheckout.embedded_publishable_key
    render :embedded_checkout
  rescue LightekCommerce::StripeCheckout::Unavailable => error
    redirect_to commerce_shop_path(site_id: @site.id), alert: error.message
  end

  private

  def completion_url(order, instance_cart)
    instance_cart ? installation_url(order) : commerce_shop_url(site_id: @site.id, order_id: order.id)
  end

  def checkout_selection
    return [cart, nil] unless workspace_in_cart

    product_id, seats = cart.first
    [{product_id => 1}, seats]
  end

  def select_workspace(product, quantity, seat_range)
    limit = Gatekeeper::Hosting::WorkspacePlans.checkout_seat_limit(starting_price: product.price_cents, seat_range: seat_range)
    if params[:variant_id].present? || !quantity.between?(seat_range.begin, limit)
      return redirect_to commerce_shop_path(site_id: @site.id), alert: "Choose a seat count offered by this Workspace plan."
    end
    if cart.any? && workspace_in_cart.nil?
      return redirect_to commerce_shop_path(site_id: @site.id), alert: "Check out your current cart before selecting a Workspace plan."
    end

    session[cart_key] = {product.id.to_s => quantity}
    redirect_to commerce_shop_path(site_id: @site.id), notice: "Workspace plan selected."
  end

  def workspace_in_cart
    return unless cart.size == 1 && cart.keys.first.match?(/\A[1-9]\d*\z/)

    product = LightekCommerce::Product.where(site: @site).find_by(id: cart.keys.first)
    product if product && Gatekeeper::Hosting::WorkspacePlans.seats_for(product)
  end

  def set_site
    @site = DymondSite::Site.find(params.require(:site_id))
  end
  def cart_key = "lightek_commerce_cart_#{@site.id}"
  def cart = @cart ||= session[cart_key].to_h
end
