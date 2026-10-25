# frozen_string_literal: true

class Dashboard::FinancialOperationsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def index
    @plans = DymondBank::SubscriptionPlan.order(:name).limit(12).to_a
    @subscription_total = DymondBank::Subscription.count
    @recent_subscriptions = DymondBank::Subscription.order(created_at: :desc).limit(25).to_a
    @subscription_statuses = DymondBank::Subscription.group(:status).count if DymondBank::Subscription.column_names.include?("status")
    @subscription_statuses ||= {}
    @provisioning_total = ProvisioningRequest.count if defined?(ProvisioningRequest)
    @recent_provisioning = defined?(ProvisioningRequest) ? ProvisioningRequest.order(created_at: :desc).limit(8).to_a : []
    @susu_total = SusuGroup.count if defined?(SusuGroup)
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    head :forbidden
  end
end
