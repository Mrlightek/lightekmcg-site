class Dashboard::ShippingController < Dashboard::CommerceBaseController
  protect_from_forgery with: :exception
  before_action :set_site
  rescue_from LightekShipping::Fedex::Unavailable, LightekShipping::Ups::Unavailable, LightekReservations::Federation::Client::Unavailable,
    ArgumentError, ActiveRecord::RecordInvalid, with: :shipping_error
  def index
    @profile = LightekShipping::Profile.find_or_initialize_by(site: @site)
    @quotes = LightekShipping::Quote.where(site: @site, merchandise_return_id: nil).includes(:shipment, :purchase_order).order(id: :desc).limit(50)
    if platform_carrier_operator?
      @carriers = LightekShipping::Account::PROVIDERS.map { |provider| LightekShipping::Account.find_or_initialize_by(provider: provider) }
    end
  end
  def supplies
    config = LightekReservations::Federation::Client.config(@site)
    collection = LightekShipping::Supplies::COLLECTION_SLUG
    if config
      data = LightekReservations::Federation::Client.new(@site).request('shipping/supplies')
      site_id = data['site_id']
      if site_id.is_a?(Integer) && site_id.positive?
        origin = URI.parse(config.fetch('origin'))
        origin.path = commerce_shop_path.split("?").first
        origin.query = URI.encode_www_form(site_id: site_id, collection: collection)
        return redirect_to origin.to_s, allow_other_host: true
      end
    elsif (site_id = LightekShipping::Supplies.catalog_site_id)
      return redirect_to commerce_shop_path(site_id: site_id, collection: collection)
    end

    redirect_to dashboard_shipping_path(site_id: @site.id), alert: 'The Lightek packing supplies catalog has not been published.'
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
  def pickup_rate
    @pickup_quote = scoped_quote
    @pickup = params.require(:pickup).permit(:date, :ready, :close)
    @pickup_price_cents = LightekShipping::PickupQuote.rate!(quote: @pickup_quote, attributes: @pickup)
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
    redirect_to dashboard_shipping_path(site_id: @site.id), notice: "Carrier confirmed cancellation. Payment refunds are recorded separately in Orders."
  end
  def label
    quote = scoped_quote
    if quote.broker_reference.present?
      result = LightekReservations::Federation::Client.new(@site).request("shipping/quotes/#{quote.broker_reference}/labels/#{Integer(params.fetch(:index, 0))}")
      send_shipping_label(Base64.strict_decode64(result.fetch("data")), result.fetch("content_type"))
    else
      shipment = quote.shipment || raise(ActiveRecord::RecordNotFound)
      raise ActiveRecord::RecordNotFound unless shipment.status == "ready"
      attachment = shipment.labels.attachments.order(:id).offset(Integer(params.fetch(:index, 0))).first || raise(ActiveRecord::RecordNotFound)
      send_shipping_label(attachment.download, attachment.content_type)
    end
  end
  def configure_carrier
    raise CanCan::AccessDenied unless platform_carrier_operator?

    provider = params.fetch(:provider, 'fedex')
    raise ArgumentError, 'Unsupported carrier' unless provider.in?(LightekShipping::Account::PROVIDERS)

    account = LightekShipping::Account.find_or_initialize_by(provider: provider)
    fields = %i[sandbox enabled production_approved]
    fields += %i[markup_bps fixed_markup_cents minimum_margin_cents] if provider == 'fedex'
    settings = params.require(:carrier).permit(*fields)
    credential_fields = %i[client_id client_secret account_number]
    credential_fields += %i[grant_type child_key child_secret] if provider == 'fedex'
    values = params.fetch(:credentials, ActionController::Parameters.new).permit(*credential_fields).to_h.reject { |_, value| value.blank? }
    account.assign_attributes(settings.merge(credential_slug: "lightek-#{provider}-platform"))
    account.validate!
    name = provider == 'ups' ? 'UPS' : 'FedEx'
    if values.present?
      raise ArgumentError, "Provide the #{name} API key, API secret and Lightek account number together" unless %w[client_id client_secret account_number].all? { |key| values[key].present? }
      LightekVault::Service.store!(name: "Lightek #{name} carrier account", slug: account.credential_slug, payload: values, provider: provider, purpose: "carrier_shipping",
        access_policy: {"consumers" => [account.carrier_class::CONSUMER], "purposes" => ["carrier_shipping"]}, requested_by: current_user.email_address)
    end
    if account.enabled? && values.blank? && !LightekVault::Secret.active.exists?(slug: account.credential_slug)
      raise ArgumentError, "Connect the #{name} account before enabling shipping"
    end

    account.save!
    account.touch if values.present?
    redirect_to dashboard_shipping_path(site_id: @site.id), notice: "#{name} carrier settings saved."
  end

  private

  def platform_carrier_operator?
    current_user.role == 'super_admin' && LightekReservations::Federation::Client.config(@site).blank?
  end

  def send_shipping_label(bytes, content_type)
    extension = {'application/pdf' => 'pdf', 'image/gif' => 'gif'}[content_type]
    raise ArgumentError, 'Unsupported shipping label format' unless extension

    send_data bytes, type: content_type, disposition: 'attachment', filename: "shipping-label.#{extension}"
  end

  def set_site
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first!
  end
  def scoped_quote = LightekShipping::Quote.where(site: @site, merchandise_return_id: nil).find_by!(public_key: params.require(:key))
  def shipping_error(error)
    redirect_to dashboard_shipping_path(site_id: params[:site_id]), alert: error.message
  end
end
