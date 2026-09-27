class Dashboard::SubscriptionPlansController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!
  before_action :set_plan, only: %i[edit update destroy]

  def index
    @plans = DymondBank::SubscriptionPlan.order(:sort_order, :name)
  end

  def new
    @plan = DymondBank::SubscriptionPlan.new(active: true)
    load_dependencies
  end

  def create
    @plan = DymondBank::SubscriptionPlan.create!(plan_params)
    sync_entitlement!(@plan)
    redirect_to dashboard_subscription_plans_path, notice: "Subscription plan created."
  rescue StandardError => e
    @plan ||= DymondBank::SubscriptionPlan.new(plan_params)
    load_dependencies
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def edit
    load_dependencies
  end

  def update
    @plan.update!(plan_params)
    sync_entitlement!(@plan)
    redirect_to dashboard_subscription_plans_path, notice: "Subscription plan updated."
  rescue StandardError => e
    load_dependencies
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @plan.destroy!
    redirect_to dashboard_subscription_plans_path, notice: "Subscription plan deleted."
  rescue StandardError => e
    redirect_to dashboard_subscription_plans_path, alert: e.message
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def set_plan
    @plan = DymondBank::SubscriptionPlan.find(params[:id])
  end

  def load_dependencies
    @profiles = ProvisioningProfile.active.order(:name)
    @policies = ComputePolicy.active.order(:name)
  end

  def plan_params
    params.require(:subscription_plan).permit(:slug,:name,:description,:price_monthly_cents,:price_annual_cents,:currency,:active,:sort_order)
  end

  def sync_entitlement!(plan)
    raw = params.fetch(:infrastructure_entitlement, {}).permit(:provisioning_profile_id,:compute_policy_id,:node_quantity,:auto_provision,:feature_entitlements).to_h
    features = raw.delete("feature_entitlements").to_s.split(",").map(&:strip).reject(&:blank?)
    entitlement = SubscriptionInfrastructureEntitlement.find_or_initialize_by(subscription_plan_id: plan.id)
    entitlement.assign_attributes(raw.merge("feature_entitlements" => features))
    entitlement.save!
  end
end
