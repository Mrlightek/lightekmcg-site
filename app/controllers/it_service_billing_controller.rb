class ItServiceBillingController < ApplicationController
  protect_from_forgery with: :exception
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_billing_owner!
  rescue_from ItServices::Enrollment::Invalid, LightekCommerce::OrderPlacement::Invalid,
    LightekCommerce::StripeCheckout::Unavailable, Stripe::StripeError, with: :billing_error

  def index
    @plans = catalog.includes(:product, :resource)
    @plans = @plans.where(id: params[:plan_id]) if params[:plan_id].present?
    @plans = @plans.limit(100).select(&:available?)
    @memberships = ItServices::Membership.where(customer: current_user)
      .includes(plan: { product: :site, resource: :site }, order: { commerce_subscription: :billing_invoices }).order(id: :desc).limit(100)
    @batch_b_ready = ItServices::Enrollment.operations_ready?
    if @batch_b_ready
      cases = ItServiceRequest.where(user_id: current_user.id).where.not(reservation_id: nil).select(:reservation_id)
      @appointments = LightekReservations::Reservation.where(customer: current_user, id: cases)
        .where.not(order_id: nil).includes(:order).order(starts_at: :desc).limit(50)
    end
  end

  def checkout
    unless ItServices::Enrollment.operations_ready?
      raise ItServices::Enrollment::Invalid, "IT Services booking is unavailable."
    end
    plan = catalog.find(params.require(:plan_id))
    membership = ItServices::Enrollment.reserve!(customer: current_user, plan: plan)
    session = LightekCommerce::StripeCheckout.start!(order: membership.order, success_url: it_service_billing_url, cancel_url: it_service_billing_url)
    redirect_to session.url, allow_other_host: true, status: :see_other
  end

  def cancel
    membership = ItServices::Membership.where(customer: current_user).find(params.require(:id))
    ItServices::Enrollment.cancel!(membership: membership, customer: current_user)
    redirect_to it_service_billing_path, notice: "Renewal is canceled. Paid coverage remains available until the end of the term.", status: :see_other
  end

  private

  def catalog
    @site = DymondSite::Site.find_by(host: request.host)
    ItServices::Plan.joins(:product).where(lightek_commerce_products: { site_id: @site&.id, published: true })
  end

  def require_billing_owner!
    response.headers["Cache-Control"] = "no-store, private"
    head :forbidden unless current_user&.access_active? && Current.session&.connect_delegation.blank?
  end

  def billing_error(error)
    message = error.is_a?(Stripe::StripeError) ? "Billing could not be verified. Reload to check the current status." : error.message
    redirect_to it_service_billing_path, alert: message, status: :see_other
  end
end
