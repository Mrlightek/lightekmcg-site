class SusuPayoutAccountsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  before_action :redirect_network_payouts

  def show
    @payout_schedule = LightekCommerce::PayoutSchedule.for!(current_user)
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
  private
  def redirect_network_payouts
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).detect { |record| LightekReservations::Federation::Client.config(record) }
    return unless site
    LightekReservations::Federation::Client.new(site) # Validate the configured HTTPS origin.
    connection = LightekReservations::Federation::Client.config(site)
    # Account/destination changes happen only after authenticating the central
    # merchant account; a peer token cannot change a payout destination.
    redirect_to "#{connection.fetch('origin')}/my/resort-earnings?peer=#{connection.fetch('key')}", allow_other_host: true, status: :see_other
  end
end
