# A signed, expiring customer capability. Never accepts an order ID from input.
class SalesQuotesController < ApplicationController
  allow_unauthenticated_access
  skip_authorization_check
  protect_from_forgery with: :exception
  before_action :quote!
  layout 'auth'
  rate_limit to: 10, within: 10.minutes, only: %i[accept checkout]
  rescue_from ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound do
    head :not_found
  end
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, LightekCommerce::OrderPlacement::Invalid, LightekCommerce::StripeCheckout::Unavailable do |error|
    flash.now[:alert] = error.message
    render :show, status: :unprocessable_entity
  end
  def show; end
  def accept
    raise ArgumentError, 'Review and accept the quote before continuing.' unless params[:accepted] == '1'
    LightekSales::Quotes.accept!(quote: @quote, name: params.require(:accepted_name), reference: 'Customer acknowledged the issued quote through its signed portal link')
    redirect_to public_sales_quote_path(token: params[:token]), status: :see_other
  end
  def checkout
    raise ArgumentError, 'Accept this quote before checkout.' unless @quote.status == 'accepted' && @quote.order
    return_url = public_sales_quote_url(token: params[:token])
    embedded = LightekCommerce::StripeCheckout.embedded_for?(@quote.order)
    checkout = LightekCommerce::StripeCheckout.start!(order: @quote.order, success_url: return_url, cancel_url: return_url, embedded: embedded)
    if checkout.url.present?
      redirect_to checkout.url, allow_other_host: true, status: :see_other
    else
      redirect_to embedded_public_sales_quote_path(token: params[:token]), status: :see_other
    end
  end

  def embedded_checkout
    raise ActiveRecord::RecordNotFound unless @quote.status == 'accepted' && @quote.order

    @completion_url = public_sales_quote_url(token: params[:token])
    return redirect_to @completion_url if @quote.order.paid_at?

    @site = @quote.site
    @checkout = LightekCommerce::StripeCheckout.resume!(order: @quote.order, embedded: true)
    @publishable_key = LightekCommerce::StripeCheckout.embedded_publishable_key
    @back_url = @completion_url
    render 'commerce/embedded_checkout'
  end
  private
  def quote!
    @quote = LightekSales::Quote.find_signed!(params[:token], purpose: 'sales_quote')
    raise ActiveRecord::RecordNotFound unless @quote.portal_host.to_s.downcase == request.host.downcase
    LightekAgency::PackagePolicy.authorize!(@quote.site.tenant, 'commerce')
    response.set_header('Cache-Control', 'private, no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
  end
end
