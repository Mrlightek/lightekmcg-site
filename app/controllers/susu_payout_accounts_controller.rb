class SusuPayoutAccountsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  def show
    return if current_user.stripe_connect_account_id.blank?
    DymondBank::StripeService.sync_connect_status!(current_user)
  rescue DymondBank::StripeService::StripeError => e
    flash.now[:alert] = "Could not refresh payout status: #{e.message}"
  end

  def connect
    link = DymondBank::StripeService.create_account_link!(
      user: current_user,
      refresh_url: refresh_dashboard_susu_payout_account_url,
      return_url: dashboard_susu_payout_account_url
    )
    redirect_to link.url, allow_other_host: true, status: :see_other
  rescue DymondBank::StripeService::ConfigurationError, DymondBank::StripeService::StripeError => e
    redirect_to dashboard_susu_payout_account_path, alert: "Payout setup could not start: #{e.message}"
  end

  def refresh
    redirect_to connect_dashboard_susu_payout_account_path, status: :see_other
  end
end
