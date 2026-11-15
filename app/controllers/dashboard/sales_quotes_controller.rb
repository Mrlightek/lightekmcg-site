class Dashboard::SalesQuotesController < Dashboard::SalesController
  skip_before_action :set_kind
  rescue_from ActiveRecord::RecordInvalid do |error|
    redirect_to dashboard_sales_path(site_id: @site.id), alert: error.record.errors.full_messages.to_sentence
  end
  rescue_from LightekCommerce::OrderPlacement::Invalid, LightekCommerce::StripeCheckout::Unavailable do |error|
    redirect_to dashboard_sales_path(site_id: @site.id), alert: error.message
  end
  def create
    quantities = params.require(:quantities).to_unsafe_h.reject { |_, quantity| quantity.to_s.blank? || quantity.to_s == '0' }
    quote = LightekSales::Quotes.new(actor: current_user, site: @site).draft!(opportunity_id: params.require(:opportunity_id),
      values: params.require(:quote).permit(:title, :customer_email, :terms, :expires_on), quantities: quantities, previous_id: params[:previous_id].presence, portal_host: request.host)
    redirect_to dashboard_sales_quote_path(site_id: @site.id, id: quote.id), status: :see_other
  end
  def show
    @quote = LightekSales::Quote.where(site: @site).includes(:opportunity, :order).find(params[:id])
    @products = LightekCommerce::Product.where(site: @site, published: true, product_type: %w[service digital lightek_instance]).order(:name)
  end
  def issue
    quote = LightekSales::Quotes.new(actor: current_user, site: @site).issue!(id: params[:id], version: params.require(:lock_version))
    redirect_to dashboard_sales_quote_path(site_id: @site.id, id: quote.id), notice: 'Quote issued. Share its customer link when ready.', status: :see_other
  end
  def accept
    raise ArgumentError, 'Confirm that the customer approved this exact quote.' unless params[:confirmed] == '1'
    quote = LightekSales::Quote.where(site: @site).find(params[:id])
    LightekSales::Quotes.accept!(quote: quote, name: params.require(:accepted_name), reference: params.require(:acceptance_reference), actor: current_user)
    redirect_to dashboard_sales_quote_path(site_id: @site.id, id: quote.id), notice: 'Customer approval recorded; pending order created. Payment is confirmed separately by the processor.', status: :see_other
  end
end
