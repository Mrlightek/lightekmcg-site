class Api::CommerceNetworkController < Api::ReservationFederationController
  rescue_from LightekCommerce::MerchantPayouts::Invalid, LightekCommerce::RevenueSharing::Invalid,
    LightekCommerce::Refunds::Invalid, LightekCommerce::Fulfillment::Invalid, LightekCommerce::StripeCheckout::Unavailable,
    Stripe::StripeError, with: ->(error) { render json: {error: error.message}, status: :unprocessable_entity }
  def checkout
    values = params.require(:checkout).permit(:source_key, :customer_email, :store_name, :return_url, :shipping_quote_key, :shipping_price_cents,
      merchant_chain: %i[subject email first_name last_name role upstream_share_bps], items: %i[name quantity unit_price_cents product_type billing_interval]).to_h
    sale = LightekCommerce::NetworkGateway.reserve!(peer: @peer, attributes: values)
    render json: LightekCommerce::NetworkGateway.checkout!(sale)
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
    Stripe.api_key = DymondBank::StripeCredentials.secret_key
    merchant.with_lock do
      if merchant.stripe_connect_account_id.blank?
        account = Stripe::Account.create({type: "express", email: merchant.email_address, capabilities: {transfers: {requested: true}}},
          {idempotency_key: "lightek-network-connect-user-#{merchant.id}"})
        merchant.update!(stripe_connect_account_id: account.id)
      end
    end
    link = Stripe::AccountLink.create(account: merchant.stripe_connect_account_id, type: "account_onboarding", return_url: destination, refresh_url: destination)
    render json: {url: link.url}
  end
  def summary
    values = params.permit(:store_name, merchant_chain: %i[subject email first_name last_name role upstream_share_bps]).to_h
    merchant, = LightekCommerce::NetworkAccounts.resolve!(peer: @peer, chain: values.fetch("merchant_chain"), store_name: values.fetch("store_name"))
    DymondBank::StripeService.sync_connect_status!(merchant) if merchant.stripe_connect_account_id.present?
    shares = LightekCommerce::RevenueAllocation.where(beneficiary: merchant)
    render json: {connect_ready: merchant.stripe_connect_ready?, earned_share_cents: shares.sum("amount_cents - reversed_cents"),
      pending_share_cents: shares.where(status: "pending").sum("amount_cents - reversed_cents")}
  end
  private
  def sale = @sale ||= LightekCommerce::NetworkSale.where(peer: @peer).find_by!(public_key: params.require(:key))
  def scoped_order = LightekCommerce::NetworkGateway.order_for(sale, invoice_reference: params[:invoice_reference])
end
