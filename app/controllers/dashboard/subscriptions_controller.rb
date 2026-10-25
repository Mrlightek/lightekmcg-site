# frozen_string_literal: true
# V8.6D: read-only administrative subscription registry.
# Money-changing operations belong to Dymond Bank lifecycle services, not this controller.
class Dashboard::SubscriptionsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def index
    @subscriptions = DymondBank::Subscription.order(id: :desc).limit(100)
  end

  def show
    @subscription = DymondBank::Subscription.find(params[:id])
  end

  # V8_6E_ADMIN_CANCEL: cancel through the canonical Dymond Bank model lifecycle.
  def cancel
    subscription = DymondBank::Subscription.find(params[:id])
    subscription.with_lock do
      subscription.cancel! unless subscription.status.to_s.in?(%w[canceled cancelled])
    end
    redirect_to dashboard_subscription_path(subscription), notice: "Subscription cancellation processed by Dymond Bank."
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    head :forbidden
  end
end
