class Dashboard::ShippingController < Dashboard::CommerceBaseController
  protect_from_forgery with: :exception
  before_action :set_site, except: :configure_carrier
  rescue_from LightekShipping::Fedex::Unavailable, LightekReservations::Federation::Client::Unavailable,
    ArgumentError, ActiveRecord::RecordInvalid, with: :shipping_error
  def index
    @profile = LightekShipping::Profile.find_or_initialize_by(site: @site)
    @quotes = LightekShipping::Quote.where(site: @site).includes(:shipment, :purchase_order).order(id: :desc).limit(50)
    @carrier = LightekShipping::Account.find_or_initialize_by(provider: "fedex") if current_user.role == "super_admin"
  end
  def profile
    profile = LightekShipping::Profile.find_or_initialize_by(site: @site)
    profile.update!(params.require(:profile).permit(:customer_markup_bps, origin: %i[name phone street city state postal_code country residential], default_package: %i[weight_lb length_in width_in height_in]))
    redirect_to dashboard_shipping_path(site_id: @site.id), notice: "Shipping origin and packaging saved."
  end
  def quote
    profile = LightekShipping::Profile.find_by!(site: @site)
    recipient = params.require(:recipient).permit(:name, :phone, :street, :city, :state, :postal_code, :country).to_h
    LightekShipping::Quotes.create!(site: @site, origin: profile.origin, recipient: recipient, packages: [profile.default_package])
    redirect_to dashboard_shipping_path(site_id: @site.id), notice: "Shipping rates are ready. Choose a service to purchase its label."
  end
  def purchase
    quote = scoped_quote
    config = LightekReservations::Federation::Client.config(@site)
    return_url = if config
      host = config["client_host"].presence || ENV["LIGHTEK_DEPLOYED_SITE_HOST"].presence || @site.host
      "https://#{host}/dashboard/shipping?site_id=#{@site.id}"
    else
      dashboard_shipping_url(site_id: @site.id)
    end
    url = LightekShipping::Purchases.start!(quote: quote, email: current_user.email_address, return_url: return_url)
    redirect_to url, allow_other_host: true
  end
  def refresh
    quote = scoped_quote
    LightekShipping::Labels.refresh!(quote: quote)
    redirect_to dashboard_shipping_path(site_id: @site.id), notice: "Shipment status refreshed."
  end
  def cancel
    LightekShipping::Labels.cancel!(quote: scoped_quote)
    redirect_to dashboard_shipping_path(site_id: @site.id), notice: "FedEx confirmed cancellation. Payment refunds are recorded separately in Orders."
  end
  def label
    quote = scoped_quote
    if quote.broker_reference.present?
      result = LightekReservations::Federation::Client.new(@site).request("shipping/quotes/#{quote.broker_reference}/labels/#{Integer(params.fetch(:index, 0))}")
      send_data Base64.strict_decode64(result.fetch("data")), type: "application/pdf", disposition: "attachment", filename: "shipping-label.pdf"
    else
      shipment = quote.shipment || raise(ActiveRecord::RecordNotFound)
      raise ActiveRecord::RecordNotFound unless shipment.status == "ready"
      attachment = shipment.labels.attachments.order(:id).offset(Integer(params.fetch(:index, 0))).first || raise(ActiveRecord::RecordNotFound)
      send_data attachment.download, type: "application/pdf", disposition: "attachment", filename: attachment.filename.to_s
    end
  end
  def configure_carrier
    raise CanCan::AccessDenied unless current_user.role == "super_admin"
    account = LightekShipping::Account.find_or_initialize_by(provider: "fedex")
    settings = params.require(:carrier).permit(:sandbox, :enabled, :production_approved, :markup_bps, :fixed_markup_cents, :minimum_margin_cents)
    values = params.require(:credentials).permit(:client_id, :client_secret, :account_number, :grant_type, :child_key, :child_secret).to_h.reject { |_, value| value.blank? }
    account.assign_attributes(settings.merge(credential_slug: "lightek-fedex-platform"))
    account.validate!
    if values.present?
      raise ArgumentError, "Provide the FedEx API key, API secret and Lightek account number together" unless %w[client_id client_secret account_number].all? { |key| values[key].present? }
      LightekVault::Service.store!(name: "Lightek FedEx carrier account", slug: account.credential_slug, payload: values, provider: "fedex", purpose: "carrier_shipping",
        access_policy: {"consumers" => [LightekShipping::Fedex::CONSUMER], "purposes" => ["carrier_shipping"]}, requested_by: current_user.email_address)
    end
    unless values.present? || LightekVault::Secret.active.exists?(slug: account.credential_slug)
      raise ArgumentError, "Connect the FedEx account before enabling shipping"
    end
    account.save!
    redirect_to dashboard_shipping_path(site_id: params[:site_id]), notice: "Carrier connection and retail margin saved."
  end
  private
  def set_site
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first!
  end
  def scoped_quote = LightekShipping::Quote.where(site: @site).find_by!(public_key: params.require(:key))
  def shipping_error(error)
    redirect_to dashboard_shipping_path(site_id: params[:site_id]), alert: error.message
  end
end
