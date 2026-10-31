# frozen_string_literal: true
class InstallationsController < ApplicationController
  skip_authorization_check
  layout "installations"
  before_action :private_response
  rate_limit to: 5, within: 1.minute, only: %i[access retry_installation]
  protect_from_forgery with: :exception

  def index
    @orders = LightekCommerce::Installations.scope_for(current_user).includes(items: :product).order(created_at: :desc).limit(100)
    @products = LightekCommerce::Product.visible.where(product_type: "lightek_instance").where.not(subscription_plan_id: nil).limit(20)
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

  def access
    order = customer_order
    url = Gatekeeper::WebsiteDeployment.owner_password_setup_url!(actor: current_user, order: order)
    redirect_to url, allow_other_host: true, status: :see_other
  rescue Gatekeeper::WebsiteDeployment::Invalid
    redirect_to installation_path(order), alert: "Password setup is temporarily unavailable. Your installation has been preserved."
  end

  private

  def customer_order
    scope = LightekCommerce::Installations.scope_for(current_user)
    scope = LightekCommerce::Installations.scope_for(current_user, operator: true) if current_user.role == "super_admin"
    scope.find(params.require(:id))
  end

  def private_response
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Referrer-Policy"] = "no-referrer"
  end
end
