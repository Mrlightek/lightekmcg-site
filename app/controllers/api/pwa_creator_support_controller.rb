module Api
  class PwaCreatorSupportController < ApplicationController
    allow_unauthenticated_access only: :show
    skip_authorization_check
    protect_from_forgery with: :exception
    before_action :context
    before_action { response.set_header('Cache-Control', 'private, no-store') }
    rescue_from LightekPwa::Policy::Denied do |e|
      render json: {error: e.message}, status: :forbidden
    end
    rescue_from LightekPwa::CreatorSupport::Unavailable, LightekPwa::CreatorSettlement::Unavailable,
      LightekCommerce::StripeCheckout::Unavailable, LightekPayments::PayoutAccounts::Unavailable, ActiveRecord::RecordInvalid, ArgumentError do |e|
      render json: {error: e.message}, status: :unprocessable_entity
    end
    rescue_from Stripe::StripeError do
      render json: {error: 'Payment processing is temporarily unavailable. Refresh your payment status before retrying.'}, status: :service_unavailable
    end
    def show
      offer = LightekPwa::CreatorOffer.find_by(site: @site, creator: @creator)
      payments = current_user && LightekPwa::CreatorPayment.where(site: @site, creator: @creator, supporter: current_user, kind: 'subscription').includes(order: :commerce_subscription)
      active = payments&.detect(&:active_subscription?)
      managed = payments&.detect { |p| p.order.commerce_subscription&.status.in?(%w[active past_due unpaid incomplete paused]) }
      post = params[:post_id].present? && Post.find_by!(id: params[:post_id], site: @site, user: @creator, visibility: 'public', audience: 'everyone', moderation_state: 'published')
      raise ActiveRecord::RecordNotFound if post && post.expires_at && post.expires_at.past?
      gifts = LightekPwa::CreatorEarning.joins(:creator_payment).where(lightek_pwa_creator_payments: {site_id: @site.id, creator_id: @creator.id, kind: 'gift', post_id: post ? post.id : -1})
        .where(state: %w[held available transfer_pending transferred]).order(id: :desc).limit(20).filter_map do |e|
          next if e.order.refunds.where(status: %w[pending succeeded]).exists? || e.hold_reason == 'Refund or dispute under review'
          {id: e.id, principal_cents: e.principal_cents, supporter: e.creator_payment.supporter.profile&.public_display_name}
        end
      render json: {creator: {id: @creator.profile.id, name: @creator.profile.public_display_name}, enabled: !!(LightekPwa::CreatorSupport.enabled?(@site) && offer&.enabled?),
        monthly_cents: offer&.monthly_cents, available: LightekPwa::CreatorSupport.enabled?(@site), offer_enabled: !!offer&.enabled?, subscribed: !!active, subscription_id: managed&.id, subscription_status: managed&.order&.commerce_subscription&.status, cancel_at_period_end: managed&.order&.commerce_subscription&.cancel_at_period_end, gifts: gifts}
    end
    def payments
      render json: {payments: LightekPwa::CreatorPayment.where(site: @site, creator: @creator, supporter: current_user).order(id: :desc).limit(20).map { |p|
        {id: p.id, kind: p.kind, principal_cents: p.principal_cents, status: p.order.status, fee_cents: p.fee_cents, confirmed: p.order.paid_at? && %w[paid fulfilled].include?(p.order.status)}
      }}
    end
    def quote
      render json: LightekPwa::CreatorSupport.quote(site: @site, creator: @creator, kind: params.require(:kind), principal_cents: params[:principal_cents], post_id: params[:post_id])
    end
    def checkout
      checkout = LightekPwa::CreatorSupport.checkout!(site: @site, supporter: current_user, creator: @creator, kind: params.require(:kind),
        principal_cents: params[:principal_cents], accepted_fee_cents: params.require(:accepted_fee_cents), post_id: params[:post_id], request_key: params.require(:request_key),
        success_url: request.base_url + '/lightek/index.html#/support/processing', cancel_url: request.base_url + '/lightek/index.html#/support/canceled')
      render json: {checkout_url: checkout.url}
    end
    def resume
      payment = LightekPwa::CreatorPayment.where(site: @site, creator: @creator, supporter: current_user).find(params.require(:payment_id))
      raise LightekPwa::CreatorSupport::Unavailable, 'This creator is not accepting payments' unless LightekPwa::CreatorSupport.enabled?(@site) && LightekPwa::CreatorOffer.exists?(site: @site, creator: @creator, enabled: true)
      checkout = LightekCommerce::StripeCheckout.start!(order: payment.order, success_url: request.base_url + '/lightek/index.html#/support/processing', cancel_url: request.base_url + '/lightek/index.html#/support/canceled')
      render json: {checkout_url: checkout.url}
    end
    def configure
      raise LightekPwa::Policy::Denied, 'Only the creator can change support settings' unless @creator == current_user
      offer = LightekPwa::CreatorSupport.offer!(site: @site, creator: current_user, monthly_cents: params.require(:monthly_cents), enabled: params[:enabled] == true)
      render json: {enabled: offer.enabled?, monthly_cents: offer.monthly_cents}
    end
    def cancel
      payment = LightekPwa::CreatorPayment.where(site: @site, creator: @creator, supporter: current_user, kind: 'subscription').find(params.require(:subscription_id))
      raise LightekPwa::CreatorSupport::Unavailable, 'No renewable subscription' unless payment.order.commerce_subscription&.status.in?(%w[active past_due unpaid incomplete paused])
      LightekCommerce::SubscriptionCancellation.schedule!(subscription: payment.order.commerce_subscription)
      show
    end
    def earnings
      raise LightekPwa::Policy::Denied, 'Only the creator can view earnings' unless @creator == current_user
      render json: {earnings: LightekPwa::CreatorEarning.joins(:creator_payment).where(lightek_pwa_creator_payments: {site_id: @site.id, creator_id: current_user.id}).order(id: :desc).limit(100).map { |e|
        {id: e.id, principal_cents: e.principal_cents, state: e.state, hold_reason: e.hold_reason, available_at: e.available_at, kind: e.creator_payment.kind}
      }}
    end
    def release
      earning = LightekPwa::CreatorEarning.joins(:creator_payment).where(lightek_pwa_creator_payments: {site_id: @site.id, creator_id: current_user.id}).find(params.require(:earning_id))
      result = LightekPwa::CreatorSettlement.release!(earning: earning, actor: current_user)
      render json: {id: result.id, state: result.state, message: 'Transferred to your verified payout account. Bank delivery follows your account’s payout schedule.'}
    end
    private
    def require_authentication
      return render json: {error: 'Sign in to support a creator'}, status: :unauthorized unless authenticated?
      super
    end
    def context
      authenticated?
      @site = LightekPwa::SiteContext.resolve(request.host)
      LightekPwa::Policy.new(user: current_user, site: @site).authorize!
      @creator = Profile.find(params.require(:profile_id)).user
      LightekPwa::Policy.new(user: @creator, site: @site).authorize!
    end
  end
end
