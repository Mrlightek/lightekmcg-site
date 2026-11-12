class Api::ShippingBrokerController < Api::ReservationFederationController
  rescue_from LightekShipping::Fedex::Unavailable, with: ->(error) { render json: {error: error.message}, status: :service_unavailable }
  def quotes
    values = params.permit(origin: %i[name phone street city state postal_code country residential],
      recipient: %i[name phone street city state postal_code country residential], packages: %i[weight_lb length_in width_in height_in]).to_h
    quotes = LightekShipping::Quotes.create!(site: @peer.site, origin: values.fetch("origin"), recipient: values.fetch("recipient"), packages: values.fetch("packages"), gateway: false)
    render json: {quotes: quotes.map(&:public_attributes)}
  end
  def purchase
    quote = scoped_quote
    sale = LightekCommerce::NetworkSale.joins(:order).find_by(lightek_commerce_orders: {shipping_quote_id: quote.id})
    raise ArgumentError, "The merchandise checkout already includes this shipping label" if sale
    url = URI.parse(params.require(:return_url))
    raise ArgumentError, "Invalid return address" unless url.is_a?(URI::HTTPS) && url.host == @peer.site.host && !url.userinfo && url.path == "/dashboard/shipping" && !url.fragment
    checkout = LightekShipping::Purchases.start!(quote: quote, email: @peer.merchant.email_address, return_url: url.to_s)
    render json: {url: checkout}
  end
  def status
    quote = scoped_quote
    shipment = quote.shipment
    LightekShipping::Labels.refresh!(quote: quote) if shipment&.status == "ready"
    if quote.purchase_order&.paid_at? && !shipment
      LightekShipping::LabelJob.perform_later(quote.purchase_order_id)
    end
    render json: {status: shipment&.status || "queued", tracking_number: shipment&.tracking_number,
      carrier_status: shipment&.carrier_status, label_count: shipment&.labels&.size.to_i}
  end
  def label
    shipment = scoped_quote.shipment || raise(ActiveRecord::RecordNotFound)
    raise ActiveRecord::RecordNotFound unless shipment.status == "ready"
    attachment = shipment.labels.attachments.order(:id).offset(Integer(params[:index])).first || raise(ActiveRecord::RecordNotFound)
    render json: {filename: attachment.filename.to_s, content_type: "application/pdf", data: Base64.strict_encode64(attachment.download)}
  end
  def cancel
    LightekShipping::Labels.cancel!(quote: scoped_quote)
    render json: {status: "canceled"}
  end
  private
  def scoped_quote
    original = LightekShipping::Quote.where(site: @peer.site).find_by!(public_key: params.require(:key))
    sale = LightekCommerce::NetworkSale.find_by(peer: @peer, source_shipping_quote: original)
    sale&.order&.shipping_quote || original
  end
end
