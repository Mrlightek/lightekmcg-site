# frozen_string_literal: true
require 'csv'
class Dashboard::CommercePayoutsController < Dashboard::CommerceBaseController
  include LightekIdentity::SensitiveSession
  before_action :require_sensitive_session!
  rate_limit to: 1, within: 5.minutes, only: :refresh_disputes, by: -> { current_user&.id || request.remote_ip }
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
    @processor_available = @order.paid_at? && @order.payment_provider.in?(%w[stripe stripe_invoice stripe_gift_split]) && @order.cash_paid_cents.positive?
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
    if LightekReservations::Federation::Client.config(@site)
      client = LightekReservations::Federation::Client.new(@site)
      receipt = client.synchronize_payouts!(merchant: current_user)
      return redirect_to client.commerce_finance_url(site_id: receipt['ledger_site_id']), allow_other_host: true
    end

    if params[:from].present? || params[:through].present? || request.format.csv?
      @from = parse_deposit_date(params[:from])
      @through = parse_deposit_date(params[:through])
    end
    service = bank_deposit_service
    if request.format.csv?
      csv = CSV.generate do |output|
        output << %w[row_type payout_id arrival_date payout_status reconciliation_status transaction_id category order_id gross_cents fee_cents net_cents currency]
        service.each_payout(from: @from, through: @through) do |payout|
          context = [payout.id, Time.at(payout.arrival_date).utc.to_date, safe_csv_label(payout.status),
            safe_csv_label(payout.reconciliation_status)]
          output << ['payout', *context, nil, nil, nil, nil, nil, payout.amount, payout.currency]
          service.each_transaction(payout) do |row|
            output << ['transaction', *context, row[:id], safe_csv_label(row[:category]), row[:order]&.id,
              row[:gross_cents], row[:fee_cents], row[:net_cents], row[:currency]]
          end
        end
      end
      return send_data csv, filename: "bank-deposits-#{@from}-#{@through}.csv", type: 'text/csv'
    end

    @payouts = service.list(after: params[:after], from: @from, through: @through)
  rescue LightekCommerce::BankDeposits::Unavailable, LightekReservations::Federation::Client::Unavailable => error
    flash.now[:alert] = error.message
    render :bank_deposits, formats: [:html], status: :unprocessable_entity
  end

  def bank_deposit
    load_merchant_site
    service = bank_deposit_service
    @deposit = service.detail(id: params[:payout_id], after: params[:after])
    respond_to do |format|
      format.html
      format.csv do
        csv = CSV.generate do |output|
          output << %w[payout_id transaction_id category order_id gross_cents fee_cents net_cents currency]
          service.each_transaction(@deposit.fetch(:payout)) do |row|
            output << [@deposit.fetch(:payout).id, row[:id], safe_csv_label(row[:category]), row[:order]&.id,
              row[:gross_cents], row[:fee_cents], row[:net_cents], row[:currency]]
          end
        end
        send_data csv, filename: "bank-deposit-#{@deposit.fetch(:payout).id}.csv", type: 'text/csv'
      end
    end
  rescue LightekCommerce::BankDeposits::Unavailable => error
    redirect_to dashboard_commerce_bank_deposits_path(site_id: @site.id), alert: error.message
  end

  def dispute_queue
    load_merchant_site
    if LightekReservations::Federation::Client.config(@site)
      client = LightekReservations::Federation::Client.new(@site)
      receipt = client.synchronize_payouts!(merchant: current_user)
      return redirect_to client.commerce_finance_url(site_id: receipt['ledger_site_id'], disputes: true), allow_other_host: true
    end

    scope = LightekCommerce::DisputeCase.where(order: LightekCommerce::Order.visible.where(site: @site))
    scope = scope.where(status: LightekCommerce::MerchantDisputes::RESPONDABLE) if params[:needs_response] == '1'
    scope = scope.where('id < ?', params[:after].to_i) if params[:after].present?
    @cases = scope.includes(:order).order(id: :desc).limit(51).to_a
    if @cases.size > 50
      @cases.pop
      @next_case = @cases.last.id
    end
  rescue LightekReservations::Federation::Client::Unavailable => error
    flash.now[:alert] = error.message
    render :dispute_queue, status: :unprocessable_entity
  end

  def refresh_disputes
    load_merchant_site
    raise ActiveRecord::RecordNotFound if LightekReservations::Federation::Client.config(@site)

    LightekCommerce::DisputeHistoryJob.perform_later(@site.id, current_user.id)
    redirect_to dashboard_commerce_disputes_path(site_id: @site.id),
      notice: 'Dispute history is being checked. Refresh this page for updates.', status: :see_other
  end

  def disputes
    load_merchant_order
    if @order.payment_provider == 'network'
      client = LightekCommerce::NetworkCheckout.client(@order)
      links = client.request("commerce/orders/#{@order.network_reference}")
      if @order.network_invoice_reference.present?
        invoice = Array(links['invoices']).find { |row| row['reference'] == @order.network_invoice_reference }
        links = invoice&.fetch('order') || {}
      end
      raise ActiveRecord::RecordNotFound unless links['ledger_order_id'].present?

      return redirect_to client.commerce_finance_url(site_id: links['ledger_site_id'],
        order_id: links['ledger_order_id']), allow_other_host: true
    end

    @disputes = dispute_service.list
  rescue LightekCommerce::MerchantDisputes::Unavailable, LightekPayments::PayoutAccounts::Unavailable,
    LightekReservations::Federation::Client::Unavailable, ::Stripe::StripeError
    flash.now[:alert] = 'The order’s disputes are temporarily unavailable.'
    render :disputes, status: :unprocessable_entity
  end

  def respond_to_dispute
    load_merchant_order
    files = params[:merchant_dispute_files]
    attachments = if files.is_a?(ActionController::Parameters)
      files.permit(*LightekCommerce::MerchantDisputes::EVIDENCE_FIELDS.keys).to_h
    else
      {}
    end
    dispute_service.respond!(id: params[:dispute_id], evidence: params[:merchant_dispute_evidence],
      confirmed: params[:confirm_submission] == '1', attachments: attachments)
    redirect_to dashboard_commerce_order_disputes_path(site_id: @site.id, order_id: @order.id),
      notice: 'Response sent to the payment processor.', status: :see_other
  rescue LightekCommerce::MerchantDisputes::Unavailable, LightekPayments::PayoutAccounts::Unavailable => error
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

  def parse_deposit_date(value)
    raise ArgumentError unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    Date.iso8601(value)
  rescue ArgumentError
    raise LightekCommerce::BankDeposits::Unavailable, 'Choose a valid start and end date.'
  end

  def safe_csv_label(value)
    value.to_s[/\A[a-z0-9_]+\z/] || 'other'
  end

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
