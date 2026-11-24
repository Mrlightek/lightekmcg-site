# frozen_string_literal: true
require "base64"
class InstallationsController < ApplicationController
  skip_authorization_check
  layout "installations"
  before_action :private_response
  after_action :record_purchased_service_visit, only: :show
  rate_limit to: 5, within: 1.minute, only: %i[access retry_installation]
  protect_from_forgery with: :exception

  def index
    @orders = LightekCommerce::Installations.scope_for(current_user).includes(items: :product).order(created_at: :desc).limit(100)
    products = LightekCommerce::Product.visible.where(product_type: "lightek_instance").where.not(subscription_plan_id: nil).limit(20)
    @products, candidates = products.partition { |product| !product.full_communications_package? }
    @full_packages = LightekCommunications::FullPackageCheckout.eligible?(current_user) ?
      candidates.filter_map { |product| [product, offer] if (offer = LightekCommunications::FullPackageCheckout.offer(product)) } : []
  end

  def full_package
    @product = full_package_product
    @offer = LightekCommunications::FullPackageCheckout.offer(@product)
    raise ActiveRecord::RecordNotFound unless @offer && LightekCommunications::FullPackageCheckout.eligible?(current_user)

    @checkout_key = SecureRandom.uuid
  end

  def purchase_full_package
    @product = full_package_product
    @offer = LightekCommunications::FullPackageCheckout.offer(@product)
    @checkout_key = params.require(:checkout_key)
    setup = LightekCommunications::VoiceSetup
    fields = params.permit(number_request: %i[option area_code phone_number],
      voice_setup: [:confirm_emergency_address, :authorize_port, :document, { emergency: setup::ADDRESS_FIELDS, port: setup::PORT_FIELDS }]).to_h
    voice = fields.fetch("voice_setup", {})
    if (document = voice["document"])
      unless document.is_a?(ActionDispatch::Http::UploadedFile) && document.size.between?(1, 2.megabytes)
        raise setup::Invalid, "Upload your current carrier invoice as a PDF of up to 2 MB."
      end
      voice["document"] = Base64.strict_encode64(document.read(2.megabytes + 1))
    end
    package = LightekCommunications::FullPackageCheckout
    order = package.reserve!(actor: current_user, product: @product, checkout_key: @checkout_key,
      number_request: fields.fetch("number_request", {}), fields: voice)
    return redirect_to installation_path(order), status: :see_other if order.paid_at?

    checkout = LightekCommerce::StripeCheckout.start!(order: order,
      success_url: installation_url(order), cancel_url: installation_url(order))
    redirect_to LightekCommunications::InstallationVoice.checkout_url!(checkout.url), allow_other_host: true, status: :see_other
  rescue LightekCommunications::FullPackageCheckout::Invalid, LightekCommunications::VoiceSetup::Invalid, LightekCommunications::InstallationVoice::Unavailable,
    LightekCommerce::OrderPlacement::Invalid, LightekCommerce::StripeCheckout::Unavailable, ActiveRecord::RecordInvalid => error
    flash.now[:alert] = error.message
    return redirect_to installations_path, alert: error.message if @offer.blank?
    render :full_package, status: :unprocessable_entity
  end

  def show
    @order = customer_order
    @installation = LightekCommerce::Installations.summary(@order)
    respond_to do |format|
      format.html
      format.json { render json: @installation }
    end
  end

  def create
    product = LightekCommerce::Product.visible.where(product_type: "lightek_instance").find(params.require(:product_id))
    order = LightekCommerce::InstallationCheckout.reserve!(actor: current_user, product: product, checkout_key: params.require(:checkout_key))
    return redirect_to installation_path(order), status: :see_other if order.paid_at?

    checkout = LightekCommerce::StripeCheckout.start!(order: order,
      success_url: installation_url(order), cancel_url: installation_url(order))
    redirect_to checkout.url, allow_other_host: true, status: :see_other
  rescue LightekCommerce::InstallationCheckout::Invalid, LightekCommerce::OrderPlacement::Invalid, LightekCommerce::StripeCheckout::Unavailable, ActiveRecord::RecordInvalid
    redirect_to(order&.persisted? ? installation_path(order) : installations_path, alert: "Checkout is unavailable. Your account has not been marked paid. Please try again later.")
  end

  def retry_installation
    order = customer_order
    LightekCommerce::Installations.resume!(order)
    redirect_to installation_path(order), notice: "Your existing installation has been queued to resume."
  rescue LightekCommerce::PaidInstanceProvisioning::NotReady
    redirect_to installations_path, alert: "Payment must be confirmed before installation can resume."
  end

  def cancel_subscription
    order = customer_order
    raise ActiveRecord::RecordNotFound unless order.customer_email == current_user.email_address
    LightekCommerce::SubscriptionCancellation.schedule!(subscription: order.commerce_subscription || raise(ActiveRecord::RecordNotFound))
    redirect_to installation_path(order), notice: "Subscription cancellation scheduled for the end of the paid period."
  rescue Stripe::StripeError
    redirect_to installation_path(order), alert: "Cancellation could not be confirmed. Please retry."
  end

  def access
    order = customer_order
    if LightekCommerce::Installations.member_move_pending?(order)
      return redirect_to installation_path(order), alert: 'Your content is moving. Instance access opens after verification.'
    end
    url = Gatekeeper::WebsiteDeployment.owner_password_setup_url!(actor: current_user, order: order)
    redirect_to url, allow_other_host: true, status: :see_other
  rescue Gatekeeper::WebsiteDeployment::Invalid
    redirect_to installation_path(order), alert: "Password setup is temporarily unavailable. Your installation has been preserved."
  end

  private

  def full_package_product
    raise ActiveRecord::RecordNotFound if Current.session&.connect_delegation.present?

    product = LightekCommerce::Product.visible.where(product_type: "lightek_instance").find(params.require(:product_id))
    raise ActiveRecord::RecordNotFound unless product.full_communications_package?
    product
  end

  def record_purchased_service_visit
    return unless response.successful? && request.format.html? && Current.session&.connect_delegation.blank?

    NevaehImprovement::PurchasedService.record_visit!(current_user, @order)
  rescue StandardError => error
    Rails.logger.warn("[Nevaeh improvement] Installation visit evidence failed: #{error.class}")
  end

  def customer_order
    scope = LightekCommerce::Installations.scope_for(current_user)
    scope = LightekCommerce::Installations.scope_for(current_user, operator: true) if current_user.role == "super_admin"
    scope.find(params.require(:id))
  end

  def private_response
    response.headers["Cache-Control"] = "no-store, private"
    # Preserve same-origin form Origin headers for Rails CSRF validation.
    # Suppress referrers when handing off to the separate customer hostname.
    response.headers["Referrer-Policy"] = "same-origin"
  end
end
