module Api
  class PwaMembershipsController < ApplicationController
    allow_unauthenticated_access only: :show
    skip_authorization_check
    protect_from_forgery with: :exception
    before_action :context
    before_action { response.set_header('Cache-Control', 'private, no-store') }
    rescue_from LightekPwa::Policy::Denied do |e|
      render json: {error: e.message}, status: :forbidden
    end
    rescue_from LightekPwa::Plans::Unavailable, LightekPwa::ViewSettlement::Unavailable, LightekCommerce::StripeCheckout::Unavailable, LightekCommerce::OrderPlacement::Invalid do |e|
      render json: {error: e.message}, status: :unprocessable_entity
    end
    rescue_from Stripe::StripeError do |_e|
      render json: {error: 'Membership billing is temporarily unavailable. Your current membership is preserved.'}, status: :unprocessable_entity
    end
    def show
      data = LightekPwa::Plans.payload(user: current_user, site: @site)
      if current_user
        account = LightekMail::Account.mailboxes.find_by(user: current_user, brand_member: true)
        data[:email] = {address: account&.address, enabled: account&.enabled?, open: ENV['LIGHTEK_MEMBER_EMAIL_ENABLED'] == 'true'}
        data[:view_earnings] = LightekPwa::ViewEarning.joins(:view_batch).where(user: current_user, lightek_pwa_view_batches: {site_id: @site.id}).order(id: :desc).limit(100).map do |row|
          {id: row.id, video_id: row.video_id, month: row.view_batch.month, views: row.views, amount_cents: row.amount_cents,
            earnings_per_thousand_views_cents: row.earnings_per_thousand_views_cents, state: row.state}
        end
        data[:view_payouts_open] = ENV['LIGHTEK_VIEW_PAYOUTS_ENABLED'] == 'true'
        data[:youtube_revenue] = LightekPwa::YoutubeRevenue.where(site: @site, user: current_user).order(id: :desc).limit(100).map do |row|
          {video_id: row.video_id, period_start: row.period_start, period_end: row.period_end, reported_cents: row.amount_cents,
           creator_cents: row.creator_cents, views: row.views, earnings_per_thousand_views_cents: row.earnings_per_thousand_views_cents, currency: row.currency, status: 'reported_estimate'}
        end
      end
      render json: data
    end
    def release_views
      earning = LightekPwa::ViewEarning.joins(:view_batch).where(user: current_user, lightek_pwa_view_batches: {site_id: @site.id}).find(params.require(:earning_id))
      LightekPwa::ViewSettlement.release!(earning: earning, actor: current_user)
      show
    end
    def create
      checkout = LightekPwa::Plans.checkout!(user: current_user, site: @site, key: params.require(:plan).to_s,
        success_url: request.base_url + '/lightek/index.html#/membership/processing',
        cancel_url: request.base_url + '/lightek/index.html#/membership/canceled')
      render json: {checkout_url: checkout.url}
    end
    def cancel
      purchase = LightekPwa::Plans.current(current_user, @site) or raise LightekPwa::Plans::Unavailable, 'No active paid membership'
      LightekCommerce::SubscriptionCancellation.schedule!(subscription: purchase.order.commerce_subscription)
      show
    end
    private
    def context
      authenticated?
      @site = LightekPwa::SiteContext.resolve(request.host)
      LightekPwa::Policy.new(user: current_user, site: @site).authorize!
    end
    def require_authentication
      return render json: {error: 'Sign in to manage membership'}, status: :unauthorized unless authenticated?
      super
    end
  end
end
