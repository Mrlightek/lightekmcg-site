# frozen_string_literal: true
class CommerceController < ApplicationController
  allow_unauthenticated_access only: %i[index add remove apply_discount]
  helper LightekDesign::StudioHelper
  helper DymondDash::TemplateSchemaHelper
  skip_authorization_check
  before_action :set_site
  layout 'auth', only: %i[embedded_checkout account account_returns]
  rate_limit to: 20, within: 5.minutes, only: %i[checkout buy_gift_card gift_card_balance], if: -> { action_name != 'checkout' || params[:gift_code].present? }, by: -> { current_user&.id || request.remote_ip }
  rate_limit to: 20, within: 5.minutes, only: %i[request_account_return reserve_account_exchange], by: -> { current_user.id }

  def index
    if params[:payment_intent_client_secret].present?
      response.headers['Referrer-Policy'] = 'no-referrer'
      return redirect_to commerce_shop_path(site_id: @site.id, order_id: params[:order_id].to_s), status: :see_other
    end
    if params[:order_id].present?
      order = LightekCommerce::Order.where(site: @site).find_by(id: params[:order_id])
      LightekCommerce::NetworkCheckout.synchronize!(order) if order&.payment_provider == "network"
      if order&.gift_card_redemption? && order.payment_provider == LightekCommerce::GiftCheckout::PROVIDER &&
          authenticated? && current_user&.id == order.storefront_buyer_id
        LightekCommerce::GiftCheckout.refresh!(order)
      end
    end
    @products = LightekCommerce::Product.visible.where(site: @site)
    @cart = cart
    @gift_cards_redeemable = LightekCommerce::GiftCards.redemption_enabled?(@site)
    @gift_cards_enabled = LightekCommerce::GiftCards.enabled?(@site)
    show_buyer_fee_prices
    show_discount
    keys = Array(session["lightek_shipping_quotes_#{@site.id}"]).first(10)
    @shipping_quotes = LightekShipping::Quote.where(site: @site, public_key: keys).where("expires_at > ?", Time.current)
      .where(cart_fingerprint: LightekShipping::Quotes.fingerprint(@site, @cart))
    show_shipping_promotions
    @collections = LightekCommerce::Collection.published.where(site: @site).order(:name, :id)
    if params[:collection].present?
      @collection = @collections.find_by!(slug: params[:collection])
      @collection_products = @products.where(id: @collection.products.select(:id)).includes(:variants, photos_attachments: :blob)
      if LightekDesign::Catalog.active?(@site)
        @page = Struct.new(:title, :theme, :sections).new(@collection.name, nil, [])
        return render 'commerce/collection', layout: 'lightek_design/website'
      end
      return render 'commerce/collection'
    end
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
  rescue LightekCommerce::BuyerFees::Invalid => error
    render plain: error.message, status: :service_unavailable
  rescue LightekCommerce::StripeCheckout::Unavailable, LightekCommerce::GiftCheckout::Invalid, ::Stripe::StripeError,
      LightekReservations::Federation::Client::Unavailable
    redirect_to commerce_shop_path(site_id: @site.id), alert: "Your payment status could not be confirmed. Check your receipt before trying again."
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
  def apply_discount
    if params[:remove_shipping_code].present?
      session.delete(shipping_discount_key)
      return redirect_to commerce_shop_path(site_id: @site.id, anchor: 'cart'), status: :see_other
    end
    if params.key?(:shipping_discount_code)
      code = LightekCommerce::Discount.normalize(params[:shipping_discount_code])
      unless LightekCommerce::ShippingPromotion.valid_code?(@site, code)
        raise LightekCommerce::Discounts::Invalid, 'That shipping code is unavailable for this store.'
      end

      session[shipping_discount_key] = code
      return redirect_to commerce_shop_path(site_id: @site.id, anchor: 'cart'), status: :see_other
    end

    entered = LightekCommerce::Discounts.codes(session[discount_key])
    if params[:remove_discount].present?
      entered.delete(LightekCommerce::Discount.normalize(params[:remove_discount]))
    else
      code = LightekCommerce::Discount.normalize(params[:discount_code])
      if code.present?
        entered = LightekCommerce::Discounts.codes([*entered, code])
        products = LightekCommerce::Product.visible.where(site: @site, id: cart.keys.map { |key| key.split(':').first })
        LightekCommerce::Discounts.quote(site: @site, products: products, quantities: cart, code: entered,
          buyer_id: (current_user&.id if authenticated?))
      end
    end
    session[discount_key] = entered
    redirect_to commerce_shop_path(site_id: @site.id, anchor: 'cart'), status: :see_other
  rescue LightekCommerce::Discounts::Invalid, LightekCommerce::BuyerFees::Invalid => error
    redirect_to commerce_shop_path(site_id: @site.id, anchor: 'cart'), alert: error.message, status: :see_other
  end

  def account
    response.headers['Cache-Control'] = 'private, no-store'
    @appearance = LightekCommerce::StoreAppearance.read(@site)
    orders = LightekCommerce::MerchandiseReturns.buyer_orders(site: @site, buyer: current_user)
    if params[:receipt_order_id].present?
      id = params[:receipt_order_id].to_s
      raise ActiveRecord::RecordNotFound unless id.match?(/\A[1-9][0-9]{0,17}\z/)

      @order = orders.includes(:items).find(id)
      return render :payment_receipt, formats: [:html], layout: false
    end
    @orders = orders.includes({items: :product}, shipping_quote: :shipment).order(paid_at: :desc).limit(50)
  end

  def account_returns
    response.headers['Cache-Control'] = 'private, no-store'
    @appearance = LightekCommerce::StoreAppearance.read(@site)
    @order = buyer_return_order
    @items = @order.items.includes(:product).select(&:physical_for_fulfillment?).index_by(&:id)
    returns = LightekCommerce::MerchandiseReturn.where(order_id: @order.id)
    @used = returns.counting_against_order.group(:order_item_id).sum(:quantity)
    @returns = returns.order(id: :desc).limit(100).to_a
    @return_labels = LightekCommerce::ReturnLabel.list_for(@returns)
    @refunds = @order.refunds.where(merchandise_return_id: @returns.map(&:id)).index_by(&:merchandise_return_id)
  end

  def account_return_label
    order = buyer_return_order
    pdf = LightekCommerce::ReturnLabels.download!(order: order, return_id: params[:return_id])
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data pdf, type: 'application/pdf', disposition: 'attachment', filename: "return-#{params[:return_id]}-label.pdf"
  end

  def request_account_return
    order = buyer_return_order
    service = LightekCommerce::MerchandiseReturns.new(order: order, actor: current_user)
    service.request!(item_id: params[:item_id], quantity: params[:quantity], reason: params[:reason],
      request_key: params[:request_key], buyer_request: true)
    redirect_to commerce_account_returns_path(order_id: order.id, site_id: @site.id),
      notice: 'Return request submitted.', status: :see_other
  rescue LightekCommerce::MerchandiseReturns::Invalid => error
    redirect_to commerce_account_returns_path(order_id: order.id, site_id: @site.id), alert: error.message, status: :see_other
  end

  def reserve_account_exchange
    order = buyer_return_order
    exchange = LightekCommerce::ReturnExchanges.new(order: order, actor: current_user)
    record = exchange.reserve_for_buyer!(params[:return_id], replacement: params[:replacement])
    message = record.exchange_status == 'shipped' ? 'Your replacement has already shipped.' : 'Replacement reserved.'
    redirect_to commerce_account_returns_path(order_id: order.id, site_id: @site.id), notice: message, status: :see_other
  rescue LightekCommerce::ReturnExchanges::Invalid, LightekCommerce::InventoryStockStates::Invalid => error
    redirect_to commerce_account_returns_path(order_id: order.id, site_id: @site.id), alert: error.message, status: :see_other
  end

  def gift_card_balance
    cards = LightekCommerce::GiftCards
    raise LightekCommerce::GiftCards::Invalid, 'Gift cards are unavailable for this store.' unless cards.redemption_enabled?(@site)

    code = params[:gift_code].to_s
    balance = if LightekReservations::Federation::Client.config(@site).present?
      remote = LightekReservations::Federation::Client.new(@site).request('commerce/gift-balance', method: :post,
        body: {gift_code: code, gift_store_key: cards.source_store_key(@site), store_name: @site.name,
          merchant_chain: LightekCommerce::NetworkCheckout.chain(@site)})
      Integer(remote.fetch('available_cents'))
    else
      cards.available_balance!(site: @site, scope: "site-#{@site.id}", code: code)
    end
    redirect_to commerce_shop_path(site_id: @site.id, anchor: 'cart'), status: :see_other,
      notice: "Gift card balance: #{helpers.number_to_currency(balance / 100.0)}."
  rescue LightekCommerce::GiftCards::Invalid, LightekReservations::Federation::Client::Unavailable,
      LightekPayments::PayoutAccounts::Unavailable
    redirect_to commerce_shop_path(site_id: @site.id, anchor: 'cart'), status: :see_other,
      alert: 'This gift card balance is unavailable for this store.'
  end

  def buy_gift_card
    order = LightekCommerce::GiftCards.purchase!(site: @site, buyer: current_user,
      customer_email: current_user.email_address, denomination: params[:denomination],
      recipient_email: params[:gift_recipient_email], delivery_date: params[:gift_delivery_date])
    embedded = LightekCommerce::StripeCheckout.embedded_for?(order, network: true)
    checkout = if LightekCommerce::NetworkCheckout.connected?(order)
      LightekCommerce::NetworkCheckout.start!(order: order, embedded: embedded)
    else
      LightekCommerce::StripeCheckout.start!(order: order, success_url: completion_url(order, false),
        cancel_url: commerce_shop_url(site_id: @site.id), embedded: embedded)
    end
    redirect_to_payment(checkout, order, false)
  rescue LightekCommerce::GiftCards::Invalid, LightekCommerce::StripeCheckout::Unavailable, ActiveRecord::RecordInvalid => error
    cancel_unsubmitted_order(order)
    redirect_to commerce_shop_path(site_id: @site.id), alert: error.message, status: :see_other
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
    gift_code = params[:gift_code].to_s.strip.presence
    gift_address = params[:gift_address]
    address = gift_address.is_a?(ActionController::Parameters) ? gift_address.permit(:line1, :city, :state, :postal_code, :country).to_h : {}
    shipping_reviews = params[:shipping_reviews]
    shipping_review = shipping_reviews[quote.public_key] if quote && shipping_reviews.is_a?(ActionController::Parameters)
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: email, quantities: quantities,
      workspace_seats: workspace_seats, shipping_quote: quote, storefront: true, buyer_fee_token: params[:buyer_fee_token],
      gift_redemption: gift_code.present?, storefront_buyer: current_user, discount_code: session[discount_key], expected_discount_cents: params.fetch(:expected_discount_cents, 0),
      discount_review_token: params[:discount_review_token], shipping_review_token: shipping_review,
      shipping_discount_code: session[shipping_discount_key],
      growth_visit: LightekGrowth::Tracking.from_request(site: @site, cookies: cookies, request: request))
    embedded = LightekCommerce::StripeCheckout.embedded_for?(order, network: true)
    checkout = if gift_code && LightekCommerce::NetworkCheckout.connected?(order)
      LightekCommerce::NetworkCheckout.start!(order: order, embedded: true, gift_code: gift_code, gift_address: address)
    elsif gift_code
      LightekCommerce::GiftCheckout.start!(order: order, code: gift_code, address: address)
    else
      LightekCommerce::StripeCheckout.start!(order: order,
        success_url: completion_url(order, instance_cart), cancel_url: commerce_shop_url(site_id: @site.id), embedded: embedded)
    end
    record_platform_experiment('checkout', order) if respond_to?(:record_platform_experiment, true)
    session.delete(cart_key)
    session.delete(discount_key)
    session.delete(shipping_discount_key)
    redirect_to_payment(checkout, order, instance_cart)
  rescue LightekCommerce::OrderPlacement::Invalid, LightekCommerce::StripeCheckout::Unavailable,
    LightekCommerce::BuyerFees::Invalid, LightekCommerce::GiftCheckout::Invalid, ActiveRecord::RecordInvalid => e
    cancel_unsubmitted_order(order)
    redirect_to commerce_shop_path(site_id: @site.id), alert: e.message
  end
  def embedded_checkout
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
    order, context = owned_checkout
    @payment_order = order
    @appearance = LightekCommerce::StoreAppearance.read(@site)
    @completion_url = completion_url(order, context.last)
    return redirect_to @completion_url if order.paid_at?

    if order.payment_provider == 'network'
      LightekCommerce::NetworkCheckout.synchronize!(order) if order.gift_card_redemption?
      return redirect_to @completion_url if order.paid_at?
      @checkout, @publishable_key = LightekCommerce::NetworkCheckout.embedded_session!(order)
    elsif order.gift_card_redemption?
      LightekCommerce::GiftCheckout.refresh!(order)
      return redirect_to @completion_url if order.paid_at?
      summary = LightekCommerce::GiftCheckout.payment_summary(order)
      if summary.fetch(:cash_cents).positive?
        intent = LightekCommerce::GiftCheckout.session!(order)
        summary[:client_secret] = intent.client_secret
        @publishable_key = LightekCommerce::StripeCheckout.embedded_publishable_key
      end
      @checkout = OpenStruct.new(**summary)
    else
      @checkout = LightekCommerce::StripeCheckout.resume!(order: order, embedded: true)
      @publishable_key = LightekCommerce::StripeCheckout.embedded_publishable_key
    end
    if @checkout.respond_to?(:gift_card_tender) && @checkout.gift_card_tender
      render :gift_payment
    else
      render :embedded_checkout
    end
  rescue LightekCommerce::StripeCheckout::Unavailable, LightekCommerce::GiftCheckout::Invalid, ::Stripe::StripeError => error
    message = error.is_a?(::Stripe::StripeError) ? 'Secure payment could not load. Please retry.' : error.message
    redirect_to commerce_shop_path(site_id: @site.id), alert: message
  end

  def confirm_gift_payment
    resolve_gift_payment('gift-confirm')
  end

  def cancel_gift_payment
    resolve_gift_payment('gift-cancel')
  end

  private

  def owned_checkout
    context = session[:embedded_store_orders].to_h[params[:order_id].to_s]
    unless context && context.first(3) == [@site.id, current_user.id, request.host]
      raise ActiveRecord::RecordNotFound
    end
    order = LightekCommerce::Order.visible.where(site: @site).find(params[:order_id])
    [order, context]
  end

  def resolve_gift_payment(action)
    order, = owned_checkout
    raise ActiveRecord::RecordNotFound unless order.gift_card_redemption?

    if order.payment_provider == 'network'
      LightekCommerce::NetworkCheckout.action!(order: order, action: action)
    elsif action == 'gift-confirm'
      LightekCommerce::GiftCheckout.confirm!(order)
    else
      LightekCommerce::GiftCheckout.expire!(order)
    end
    redirect_to completion_url(order, false), status: :see_other
  rescue LightekCommerce::GiftCheckout::Invalid, LightekReservations::Federation::Client::Unavailable,
      LightekCommerce::StripeCheckout::Unavailable, ::Stripe::StripeError
    redirect_to commerce_embedded_checkout_path(site_id: @site.id, order_id: order.id),
      alert: 'The gift card payment could not be updated. Check its status before retrying.', status: :see_other
  end

  def redirect_to_payment(checkout, order, instance_cart)
    return redirect_to checkout.url, allow_other_host: true if checkout.url.present?
    return redirect_to completion_url(order, instance_cart), status: :see_other if order.paid_at?

    recent = session[:embedded_store_orders].to_h
    recent[order.id.to_s] = [@site.id, current_user.id, request.host, instance_cart]
    session[:embedded_store_orders] = recent.to_a.last(5).to_h
    redirect_to commerce_embedded_checkout_path(site_id: @site.id, order_id: order.id), status: :see_other
  end

  def cancel_unsubmitted_order(order)
    return unless order&.persisted? && order.reload.status == 'pending_payment' && order.payment_reference.blank?
    return if order.gift_card_redemption? && LightekCommerce::GiftRedemption.where(order: order).where.not(payment_attempted_at: nil).exists?

    LightekCommerce::OrderPlacement.cancel!(order)
  end

  def discount_key = "lightek_commerce_discount_#{@site.id}"

  def show_discount
    @discount_codes = LightekCommerce::Discounts.codes(session[discount_key])
    return if @cart.blank?

    ids = @cart.keys.map { |key| key.split(':').first.to_i }
    products = @products.select { |product| ids.include?(product.id) }
    @discount = LightekCommerce::Discounts.quote(site: @site, products: products,
      quantities: @cart, code: @discount_codes, buyer_id: (current_user&.id if authenticated?))
    @discount_cents = @discount&.total
    @discount_review_token = LightekCommerce::Discounts.signed_quote(@site, @discount) if @discount
    if @buyer_fee_cart && @discount_cents.to_i.positive?
      @discounted_buyer_price = LightekCommerce::BuyerFees.quote_amount(
        @buyer_fee_cart.fetch('merchant_cents') - @discount_cents
      ).fetch('buyer_cents')
    end
  rescue LightekCommerce::Discounts::Invalid, LightekCommerce::BuyerFees::Invalid => error
    @discount_error = error.message
  end

  def shipping_discount_key = "lightek_commerce_shipping_promotion_#{@site.id}"

  def show_shipping_promotions
    @shipping_promotions = {}
    service = LightekCommerce::ShippingPromotion
    config = service.settings(@site)
    return unless config['enabled'] == true

    @shipping_code_enabled = config['code'].present?
    code = session[shipping_discount_key]
    @shipping_code_applied = service.valid_code?(@site, code)
    return unless @shipping_quotes.any?

    items = @products.select { |product| @cart.keys.any? { |key| key.split(':').first == product.id.to_s } }
    return unless items.any? { |product| product.product_type == 'physical' } &&
      items.all? { |product| LightekCommerce::BuyerFees.eligible?(product) && product.billing_interval == 'one_time' }

    _, subtotal = LightekCommerce::BuyerFees.cart_price(products: items, requested: @cart, price_only: true)
    subtotal -= @discount_cents.to_i
    fee = @buyer_fee_cart ? LightekCommerce::BuyerFees.quote_amount(subtotal) : {}
    @shipping_quotes.each do |quote|
      savings = service.savings(site: @site, quote: quote, subtotal: subtotal, buyer_fee: fee, merchandise_discount: @discount, code: code)
      @shipping_promotions[quote.id] = service.signed_review(@site, quote, savings) if savings.positive?
    end
  rescue LightekCommerce::BuyerFees::Invalid
    @shipping_promotions = {}
  end

  def show_buyer_fee_prices
    return if ENV['LIGHTEK_COMMERCE_BUYER_FEE_HOSTS'].blank? || !LightekCommerce::BuyerFees.enabled?(@site)

    @buyer_fee_prices = {}
    @products.each do |product|
      next unless LightekCommerce::BuyerFees.eligible?(product) && product.price_cents.positive?
      next if product.variants.any?(&:active?)

      @buyer_fee_prices[product.id] = LightekCommerce::BuyerFees.quote_for(product)
    end
    selected = @products.select { |product| cart.keys.any? { |key| key.split(':').first == product.id.to_s } }
    price = LightekCommerce::BuyerFees.cart_price(products: selected, requested: cart)
    return unless price

    lines, @buyer_fee_cart = price
    @buyer_fee_interval = lines.first.last
    @buyer_fee_token = LightekCommerce::BuyerFees.sign(@site, lines, @buyer_fee_cart)
  rescue LightekCommerce::BuyerFees::Invalid => error
    @buyer_fee_cart_error = error.message
  end

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

  def buyer_return_order
    LightekCommerce::MerchandiseReturns.buyer_order!(site: @site, buyer: current_user, id: params[:order_id])
  end

  def set_site
    @site = DymondSite::Site.find(params.require(:site_id))
  end
  def cart_key = "lightek_commerce_cart_#{@site.id}"
  def cart = @cart ||= session[cart_key].to_h
end
