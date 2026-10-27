# frozen_string_literal: true
class Dashboard::BusinessPayoutsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :ensure_user!

  def show
    if current_user.stripe_connect_account_id.present?
      DymondBank::StripeService.sync_connect_status!(current_user)
    end
    @publishable_key = ENV["STRIPE_PUBLISHABLE_KEY"].presence
  rescue DymondBank::StripeService::StripeError => error
    flash.now[:alert] = "Payout status temporarily unavailable: #{error.message}"
  end

  def session
    # Reuse Bank's existing account creation, never create a second connected account.
    if current_user.stripe_connect_account_id.blank?
      DymondBank::StripeService.create_account_link!(
        user: current_user, refresh_url: refresh_dashboard_business_payouts_url,
        return_url: dashboard_business_payouts_url
      )
      current_user.reload
    end
    raise LightekBusiness::ConnectSession::Unavailable, "Connected account was not created." if current_user.stripe_connect_account_id.blank?
    render json: {client_secret: LightekBusiness::ConnectSession.create!(current_user)}
  rescue DymondBank::StripeService::ConfigurationError, DymondBank::StripeService::StripeError,
    LightekBusiness::ConnectSession::Unavailable => error
    render json: {error: "Payout onboarding is unavailable: #{error.message}"}, status: :service_unavailable
  end

  def refresh
    redirect_to dashboard_business_payouts_path, status: :see_other
  end

  private
  def ensure_user!
    head :unauthorized unless current_user
  end
end
