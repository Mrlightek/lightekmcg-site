# frozen_string_literal: true
require 'csv'
class Dashboard::CommercePayoutsController < Dashboard::CommerceBaseController
  include LightekIdentity::SensitiveSession
  before_action :require_sensitive_session!
  def index
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    if LightekReservations::Federation::Client.config(@site) && @site.tenant == current_user
      begin
        LightekReservations::Federation::Client.new(@site).synchronize_payouts!(merchant: current_user)
        @payout_status = {state: current_user.reload.stripe_connect_ready? ? 'ready' : 'needs_information'}
      rescue LightekReservations::Federation::Client::Unavailable
        @payout_status = {state: 'unavailable'}
        flash.now[:alert] = 'Payout status could not be verified. Please retry.'
      end
    end
    @payout_status ||= LightekPayments::PayoutAccounts.status(current_user) if @site.tenant == current_user
    @payout_schedule = LightekCommerce::PayoutSchedule.for!(current_user)
    @orders = LightekCommerce::Order.visible.where(site: @site, status: %w[fulfilled partially_refunded refunded])
      .includes(:refunds).order(created_at: :desc).limit(100)
  end

  def ledger
    response.headers['Cache-Control'] = 'private, no-store'
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    raise ActiveRecord::RecordNotFound unless @site.tenant == current_user

    @order = LightekCommerce::Order.visible.where(site: @site).find(params.require(:order_id))
    @ledger = LightekCommerce::MerchantLedger.read(order: @order, actor: current_user)
    @processor_available = @order.paid_at? && @order.payment_provider.in?(%w[stripe stripe_invoice])
    if @order.subtotal_cents.positive?
      @buyer_price = LightekCommerce::BuyerPrice.quote(merchant_cents: @order.subtotal_cents)
    end
    if @processor_available
      @ledger = LightekCommerce::MerchantLedger.read(order: @order, actor: current_user, processor: true)
    end
  rescue LightekCommerce::MerchantLedger::Invalid, LightekCommerce::MerchantPayouts::Invalid, ArgumentError => error
    flash.now[:alert] = error.message
    render :ledger, status: :unprocessable_entity
  end

  def bank_deposits
    load_merchant_site
    @payouts = bank_deposit_service.list(after: params[:after])
  rescue LightekCommerce::BankDeposits::Unavailable => error
    flash.now[:alert] = error.message
    render :bank_deposits, status: :unprocessable_entity
  end

  def bank_deposit
    load_merchant_site
    @deposit = bank_deposit_service.detail(id: params[:payout_id], after: params[:after])
    respond_to do |format|
      format.html
      format.csv do
        csv = CSV.generate do |output|
          output << %w[payout_id transaction_id category order_id gross_cents fee_cents net_cents currency]
          @deposit.fetch(:rows).each do |row|
            category = row[:category].to_s
            category = 'other' unless category.match?(/\A[a-z0-9_]+\z/)
            output << [@deposit.fetch(:payout).id, row[:id], category, row[:order]&.id,
              row[:gross_cents], row[:fee_cents], row[:net_cents], row[:currency]]
          end
        end
        send_data csv, filename: "bank-deposit-#{@deposit.fetch(:payout).id}.csv", type: 'text/csv'
      end
    end
  rescue LightekCommerce::BankDeposits::Unavailable => error
    redirect_to dashboard_commerce_bank_deposits_path(site_id: @site.id), alert: error.message
  end

  def disputes
    load_merchant_order
    @disputes = dispute_service.list
  rescue LightekCommerce::MerchantDisputes::Unavailable => error
    flash.now[:alert] = error.message
    render :disputes, status: :unprocessable_entity
  end

  def respond_to_dispute
    load_merchant_order
    dispute_service.respond!(id: params[:dispute_id], evidence: params[:merchant_dispute_evidence],
      confirmed: params[:confirm_submission] == '1')
    redirect_to dashboard_commerce_order_disputes_path(site_id: @site.id, order_id: @order.id),
      notice: 'Response sent to the payment processor.', status: :see_other
  rescue LightekCommerce::MerchantDisputes::Unavailable => error
    redirect_to dashboard_commerce_order_disputes_path(site_id: @site.id, order_id: @order.id),
      alert: error.message, status: :see_other
  end

  def schedule
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    raise ActiveRecord::RecordNotFound unless site.tenant == current_user
    cadence = params.require(:cadence)
    raise ArgumentError, 'Choose weekly or every two weeks' unless %w[weekly biweekly].include?(cadence)
    if LightekReservations::Federation::Client.config(site)
      client = LightekReservations::Federation::Client.new(site)
      client.request('payouts', method: :patch, body: {cadence: cadence, enabled: params[:enabled] == '1', merchant_chain: LightekCommerce::NetworkCheckout.chain(site), store_name: site.name})
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
      notice: "Earnings released to your payout account. Bank arrival depends on your payout schedule."
  rescue LightekCommerce::MerchantPayouts::Invalid, LightekReservations::Federation::Client::Unavailable,
      DymondBank::StripeService::StripeError,
      DymondBank::StripeService::ConfigurationError => e
    redirect_to dashboard_commerce_payouts_path(site_id: params[:site_id]), alert: "Earnings could not be released. Check payout verification and available funds, then retry."
  end

  private

  def load_merchant_site
    response.headers['Cache-Control'] = 'private, no-store'
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    raise ActiveRecord::RecordNotFound unless @site.tenant == current_user
  end

  def load_merchant_order
    load_merchant_site
    @order = LightekCommerce::Order.visible.where(site: @site).find(params.require(:order_id))
  end

  def bank_deposit_service
    LightekCommerce::BankDeposits.new(site: @site, actor: current_user)
  end

  def dispute_service
    LightekCommerce::MerchantDisputes.new(order: @order, actor: current_user)
  end
end
