class CommerceShippingQuotesController < ApplicationController
  protect_from_forgery with: :exception
  def create
    site = DymondSite::Site.find(params.require(:site_id))
    quantities = session["lightek_commerce_cart_#{site.id}"].to_h
    recipient = params.require(:recipient).permit(:name, :phone, :street, :city, :state, :postal_code, :country).to_h
    quotes = LightekShipping::Quotes.for_cart!(site: site, quantities: quantities, recipient: recipient)
    session["lightek_shipping_quotes_#{site.id}"] = quotes.first(10).map(&:public_key)
    redirect_to commerce_shop_path(site_id: site.id, anchor: "cart"), notice: "Choose your shipping service and continue to payment."
  rescue LightekShipping::Fedex::Unavailable, LightekReservations::Federation::Client::Unavailable, ArgumentError => error
    redirect_to commerce_shop_path(site_id: site.id, anchor: "cart"), alert: error.message
  end
end
