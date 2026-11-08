# frozen_string_literal: true
class Dashboard::CommercePayoutsController < Dashboard::SettingsHomeController
  def index
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    if LightekReservations::Federation::Client.config(@site) && @site.tenant == current_user
      begin
        LightekReservations::Federation::Client.new(@site).synchronize_payouts!(merchant: current_user)
      rescue LightekReservations::Federation::Client::Unavailable => error
        flash.now[:alert] = error.message
      end
    end
    @payout_schedule = LightekCommerce::PayoutSchedule.for!(current_user)
    @orders = LightekCommerce::Order.where(site: @site, status: "fulfilled")
      .includes(:refunds).order(created_at: :desc).limit(100)
  end

  def schedule
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    cadence = params.require(:cadence)
    raise ArgumentError, 'Choose weekly or every two weeks' unless %w[weekly biweekly].include?(cadence)
    if LightekReservations::Federation::Client.config(site)
      client = LightekReservations::Federation::Client.new(site)
      client.request('payouts', method: :patch, body: {cadence: cadence, enabled: params[:enabled] == '1'})
      client.synchronize_payouts!(merchant: current_user)
      return redirect_to dashboard_commerce_payouts_path(site_id: site.id), notice: 'Your network payout preference has been saved.'
    end
    schedule = LightekCommerce::PayoutSchedule.for!(current_user)
    schedule.with_lock do
      schedule.update!(cadence: cadence, enabled: params[:enabled] == '1',
        next_run_at: Time.current + (cadence == 'weekly' ? 7 : 14).days)
    end
    redirect_to dashboard_commerce_payouts_path(site_id: params.require(:site_id)), notice: 'Your payout preference has been saved.'
  rescue ArgumentError, LightekReservations::Federation::Client::Unavailable => error
    redirect_to dashboard_commerce_payouts_path(site_id: params[:site_id]), alert: error.message
  end

  def create
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    order = LightekCommerce::Order.where(site: site).find(params.require(:order_id))
    LightekCommerce::MerchantPayouts.request!(order: order, merchant: current_user)
    redirect_to dashboard_commerce_payouts_path(site_id: site.id),
      notice: "Funds transferred to your Stripe Connect account. Bank payout follows your Stripe schedule."
  rescue LightekCommerce::MerchantPayouts::Invalid, DymondBank::StripeService::StripeError,
      DymondBank::StripeService::ConfigurationError => e
    redirect_to dashboard_commerce_payouts_path(site_id: params[:site_id]), alert: e.message
  end
end
