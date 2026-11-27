class Api::CommerceNetworkController < Api::ReservationFederationController
  rescue_from LightekCommerce::MerchantPayouts::Invalid, LightekCommerce::RevenueSharing::Invalid,
    LightekCommerce::GiftCards::Invalid, LightekCommerce::GiftCheckout::Invalid, LightekPayments::PayoutAccounts::Unavailable, LightekCommerce::BuyerFees::Invalid, LightekCommerce::Refunds::Invalid, LightekCommerce::Fulfillment::Invalid, LightekCommerce::StripeCheckout::Unavailable,
    DymondBank::StripeService::ConfigurationError, with: ->(error) { render json: {error: error.message}, status: :unprocessable_entity }
  rescue_from Stripe::StripeError, DymondBank::StripeService::StripeError, with: ->(_) { render json: {error: 'Payment processing is temporarily unavailable. Retry or contact support.'}, status: :unprocessable_entity }
  def checkout
    values = params.require(:checkout).permit(:source_key, :customer_email, :store_name, :return_url, :shipping_quote_key, :shipping_price_cents, :buyer_price_cents, :discount_cents, :gift_order_purpose, :gift_store_key,
      merchant_chain: %i[subject email first_name last_name role upstream_share_bps], items: %i[name quantity unit_price_cents product_type billing_interval merchandise_discount_cents]).to_h
    sale = LightekCommerce::NetworkGateway.reserve!(peer: @peer, attributes: values)
    if sale.order.gift_card_purchase? || sale.order.gift_card_redemption?
      return render json: {key: sale.public_key, gift_ready: true, buyer_fee_cents: sale.order.buyer_fee_cents}
    end
    render json: LightekCommerce::NetworkGateway.checkout!(sale, embedded: params.dig(:checkout, :embedded) == true)
  end
  def gift_start
    address = params[:gift_address]
    fields = address.is_a?(ActionController::Parameters) ? address.permit(:line1, :city, :state, :postal_code, :country).to_h : {}
    render json: LightekCommerce::NetworkGateway.gift_checkout!(sale, embedded: params[:embedded] == true,
      code: params[:gift_code], address: fields)
  end
  def gift_balance
    cards = LightekCommerce::GiftCards
    raise ActiveRecord::RecordNotFound unless cards.platform_enabled?

    values = params.permit(:store_name, :gift_store_key, :gift_code,
      merchant_chain: %i[subject email first_name last_name role upstream_share_bps]).to_h
    scope = cards.network_scope(@peer, values.fetch('gift_store_key'))
    _, site = LightekCommerce::NetworkAccounts.resolve!(peer: @peer, chain: values.fetch('merchant_chain'),
      store_name: values.fetch('store_name'))
    render json: {available_cents: cards.available_balance!(site: site, scope: scope, code: values.fetch('gift_code'))}
  end

  def gift_confirm
    order = sale.order
    raise ActiveRecord::RecordNotFound unless order.gift_card_redemption?

    LightekCommerce::GiftCheckout.confirm!(order)
    render json: {status: 'paid'}
  end

  def gift_cancel
    order = sale.order
    raise ActiveRecord::RecordNotFound unless order.gift_card_redemption?

    LightekCommerce::GiftCheckout.expire!(order)
    render json: {status: order.reload.status}
  end

  def embedded_checkout
    response.headers['Cache-Control'] = 'private, no-store'
    render json: LightekCommerce::NetworkGateway.embedded_session!(sale)
  end
  def receipt
    render json: LightekCommerce::NetworkGateway.receipt(sale)
  end
  def fulfill
    LightekCommerce::Fulfillment.complete!(order: scoped_order, reference: params[:reference], note: params[:note])
    render json: {status: "fulfilled"}
  end
  def refund
    LightekCommerce::Refunds.issue!(order: scoped_order, amount_cents: params.require(:amount_cents))
    render json: {status: "submitted"}
  end
  def payout
    order = scoped_order
    LightekCommerce::MerchantPayouts.request!(order: order, merchant: order.site.tenant)
    render json: {status: "submitted"}
  end
  def cancel_subscription
    LightekCommerce::SubscriptionCancellation.schedule!(subscription: sale.order.commerce_subscription || raise(ActiveRecord::RecordNotFound))
    render json: {status: "scheduled"}
  end
  def connect
    values = params.permit(:return_url, :store_name, merchant_chain: %i[subject email first_name last_name role upstream_share_bps]).to_h
    destination = LightekCommerce::NetworkGateway.return_url!(@peer, values.fetch("return_url"))
    merchant, = LightekCommerce::NetworkAccounts.resolve!(peer: @peer, chain: values.fetch("merchant_chain"), store_name: values.fetch("store_name"))
    # A peer can resolve its merchant tree, but cannot obtain credentials that
    # edit bank destinations. The merchant signs in and verifies MFA centrally.
    render json: {url: "#{LightekReservations::Federation::Issuer.origin}/dashboard/susu/payout-account"}
  end

  def summary
    values = params.permit(:store_name, merchant_chain: %i[subject email first_name last_name role upstream_share_bps]).to_h
    merchant, ledger_site = LightekCommerce::NetworkAccounts.resolve!(peer: @peer, chain: values.fetch("merchant_chain"), store_name: values.fetch("store_name"))
    state = LightekPayments::PayoutAccounts.status(merchant)
    schedule = LightekCommerce::PayoutSchedule.for!(merchant)
    shares = LightekCommerce::RevenueAllocation.where(beneficiary: merchant)
    render json: {ledger_site_id: ledger_site.id, connect_ready: state[:state] == 'ready', connect_account_id: merchant.stripe_connect_account_id,
      connect_details_submitted: merchant.stripe_connect_details_submitted?, connect_payouts_enabled: state[:state] == 'ready',
      cadence: schedule.cadence, enabled: schedule.enabled?, next_run_at: schedule.next_run_at.iso8601, earned_share_cents: shares.sum("amount_cents - reversed_cents"),
      pending_share_cents: shares.where(status: "pending").sum("amount_cents - reversed_cents")}
  end
  private
  def sale = @sale ||= LightekCommerce::NetworkSale.where(peer: @peer).find_by!(public_key: params.require(:key))
  def scoped_order = LightekCommerce::NetworkGateway.order_for(sale, invoice_reference: params[:invoice_reference])
end
