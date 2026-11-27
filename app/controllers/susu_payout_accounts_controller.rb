class SusuPayoutAccountsController < ApplicationController
  skip_authorization_check
  include LightekIdentity::SensitiveSession
  before_action :require_sensitive_session!
  before_action :require_direct_owner!
  before_action :private_response!
  before_action :redirect_network_payouts, except: %i[stripe_access check_stripe_access update_stripe_browser_key]
  before_action :require_platform_operator!, only: %i[stripe_access check_stripe_access update_stripe_browser_key]
  layout 'dymond_dash/layouts/dymond_dash'
  protect_from_forgery with: :exception
  rate_limit to: 12, within: 1.minute, only: %i[account_session replace connect check_stripe_access update_stripe_browser_key], by: -> { current_user&.id || request.remote_ip }

  def show
    @payout_schedule = LightekCommerce::PayoutSchedule.for!(current_user)
    @payout_status = LightekPayments::PayoutAccounts.status(current_user)
    @payout_configuration = LightekPayments::PayoutAccounts.configuration_status
  end

  def stripe_access
    @checks = DymondBank::StripeAccessCheck::CHECKS
  end

  def check_stripe_access
    @checks = DymondBank::StripeAccessCheck::CHECKS
    @selected_check = params[:check].to_s
    @result = DymondBank::StripeAccessCheck.call(actor: current_user, check: @selected_check)
    render :stripe_access
  rescue DymondBank::StripeAccessCheck::InvalidCheck => error
    flash.now[:alert] = error.message
    render :stripe_access, status: :unprocessable_entity
  end

  def update_stripe_browser_key
    LightekPayments::StripeBrowserKey.update!(actor: current_user, key: params[:browser_key].to_s.strip)
    redirect_to dashboard_commerce_stripe_access_path, notice: 'Stripe publishable key saved.', status: :see_other
  rescue LightekPayments::StripeBrowserKey::Invalid => error
    redirect_to dashboard_commerce_stripe_access_path, alert: error.message, status: :see_other
  end

  def connection_status
    render json: LightekPayments::PayoutAccounts.status(current_user)
  end

  def account_session
    # Destination and user identity are always server-derived. Never accept a
    # connected-account ID, bank details, tax IDs or identity documents here.
    render json: LightekPayments::PayoutAccounts.session!(current_user, component: params[:component].presence || 'account-onboarding')
  rescue LightekPayments::PayoutAccounts::Unavailable => error
    render json: {error: error.message, code: error.code, replaceable: error.replaceable}, status: :unprocessable_entity
  end

  def replace
    unless params[:confirm_replacement] == '1'
      return redirect_to dashboard_susu_payout_account_path, alert: 'Confirm that a new payout connection does not recover an old account balance.', status: :see_other
    end
    LightekPayments::PayoutAccounts.replace_unavailable!(current_user)
    redirect_to dashboard_susu_payout_account_path, notice: 'A new payout connection is ready for setup. Your previous connection reference was retained for reconciliation.', status: :see_other
  rescue LightekPayments::PayoutAccounts::Unavailable => error
    redirect_to dashboard_susu_payout_account_path, alert: error.message, status: :see_other
  end

  def connect
    destination = LightekPayments::PayoutAccounts.hosted_link!(current_user,
      refresh_url: refresh_dashboard_susu_payout_account_url, return_url: dashboard_susu_payout_account_url)
    redirect_to destination, allow_other_host: true, status: :see_other
  rescue LightekPayments::PayoutAccounts::Unavailable => error
    redirect_to dashboard_susu_payout_account_path, alert: error.message, status: :see_other
  end
  def refresh
    redirect_to dashboard_susu_payout_account_path, status: :see_other
  end

  private
  # Personal earnings setup is independent of the optional Susu application.
  def package_feature = nil

  def require_platform_operator!
    head :forbidden unless current_user&.role == 'super_admin'
  end

  def require_direct_owner!
    head :forbidden if Current.session&.connect_delegation.present?
  end
  def private_response!
    response.headers['Cache-Control'] = 'no-store, private'
    response.headers['Referrer-Policy'] = 'same-origin'
    head :upgrade_required unless request.ssl? || Rails.env.development? || Rails.env.test?
  end
  def redirect_network_payouts
    host = ENV['LIGHTEK_DEPLOYED_SITE_HOST'].presence
    candidates = host ? DymondSite::Site.where(host: host) : DymondSite::Site.where(tenant: current_user)
    site = candidates.detect { |record| LightekReservations::Federation::Client.config(record) }
    return unless site
    client = LightekReservations::Federation::Client.new(site)
    connection = LightekReservations::Federation::Client.config(site)
    return if URI.parse(connection.fetch('origin')).host.to_s.casecmp?(request.host)
    # Authenticate as the actual payout owner on the platform. Neither an agency
    # role nor an installation's bearer credential can edit another user's bank.
    destination = "#{connection.fetch('origin').delete_suffix('/')}/dashboard/susu/payout-account"
    if action_name.in?(%w[show connect refresh])
      client.ensure_payout_identity!(merchant: current_user)
      redirect_to destination, allow_other_host: true, status: :see_other
    else
      render json: {error: 'Open payout setup on your central Lightek account.', url: destination}, status: :conflict
    end
  rescue LightekReservations::Federation::Client::Unavailable
    render plain: 'Your payout workspace could not be opened. Please retry or contact support.', status: :service_unavailable
  end
end
