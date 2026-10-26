# frozen_string_literal: true
# Business payout onboarding uses the existing Dymond Bank Stripe Connect service.
# External account details and identity verification remain with Stripe.
class Dashboard::BusinessPayoutsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception

  def show
    return unless current_user.stripe_connect_account_id.present?
    DymondBank::StripeService.sync_connect_status!(current_user)
  rescue DymondBank::StripeService::StripeError => error
    flash.now[:alert] = "Payout status is temporarily unavailable: #{error.message}"
  end

  def connect
    link = DymondBank::StripeService.create_account_link!(
      user: current_user,
      refresh_url: refresh_dashboard_business_payouts_url,
      return_url: dashboard_business_payouts_url
    )
    redirect_to link.url, allow_other_host: true, status: :see_other
  rescue DymondBank::StripeService::ConfigurationError, DymondBank::StripeService::StripeError => error
    redirect_to dashboard_business_payouts_path, alert: "Payout setup could not start: #{error.message}"
  end

  def refresh
    redirect_to dashboard_business_payouts_path, alert: "Your setup session expired. Select Continue setup to resume.", status: :see_other
  end
end
