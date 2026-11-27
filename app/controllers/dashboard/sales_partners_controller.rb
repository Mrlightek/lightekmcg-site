# frozen_string_literal: true

class Dashboard::SalesPartnersController < Dashboard::SalesController
  skip_before_action :set_kind
  before_action :require_site_owner!, except: :materials
  include LightekIdentity::SensitiveSession
  before_action :require_sensitive_session!, only: %i[link_recipient invite_payout_setup verify_payout_sender prepare_commission release_commission refresh_commission]
  helper NevaehHelpHelper

  rescue_from ActiveRecord::RecordInvalid do |error|
    redirect_to dashboard_sales_partners_path(site_id: @site.id), alert: error.record.errors.full_messages.to_sentence
  end
  rescue_from ArgumentError, LightekSales::CommissionDisbursements::Invalid,
    DymondBank::WorkforcePayouts::Unavailable, DymondBank::WorkforcePayouts::ProviderError do |error|
    redirect_to dashboard_sales_partners_path(site_id: @site.id), alert: error.message
  end

  def materials
    @tab = 'materials'
    @kit = Rails.root.join('docs/sales/managed-website-sales-kit.md').read
  end

  def index
    @tab = 'partners'
    @products = products.order(:name)
    @sender_configured = DymondBank::WorkforcePayouts.configured?(current_user)
    @partners = partners.includes(:product).order(:revoked_at, :name)
    @referrals = referrals.includes(:partner, :commission_payout, lead: :opportunity)
      .order(id: :desc).limit(100)
  end

  def create
    fields = params.require(:partner).permit(:name, :agreement_reference, :commission, :product_id)
    amount = fields.delete(:commission).to_s.strip
    unless amount.match?(/\A\d{1,7}(?:\.\d{1,2})?\z/)
      raise ArgumentError, 'Enter a USD commission with up to two decimal places.'
    end

    @site.with_lock do
      require_site_owner!
      product = products.find(fields.delete(:product_id))
      partners.create!(fields.to_h.merge(product: product, commission_cents: (BigDecimal(amount) * 100).to_i))
    end
    redirect_to dashboard_sales_partners_path(site_id: @site.id), notice: 'Partner registered.', status: :see_other
  end

  def revoke
    @site.with_lock do
      require_site_owner!
      partner = partners.find(params[:id])
      partner.update!(revoked_at: Time.current) unless partner.revoked_at?
    end
    redirect_to dashboard_sales_partners_path(site_id: @site.id), notice: 'Referral link revoked.', status: :see_other
  end

  def invite_payout_setup
    email = params.require(:recipient).permit(:email).fetch(:email).to_s.strip.downcase
    partner = @site.with_lock do
      require_site_owner!
      record = partners.active.find(params[:id])
      if record.payout_setup_started_at? || record.payout_recipient_ref?
        raise ArgumentError, 'Payout setup has already started for this partner.'
      end
      unless email.match?(URI::MailTo::EMAIL_REGEXP)
        raise ArgumentError, 'Enter the email address the partner uses to sign in.'
      end

      record.update!(payout_email: email, payout_invited_by: current_user)
      record
    end
    SalesPartnerPayoutMailer.setup(partner.id, email, current_user.id).deliver_later
    payout_redirect('Payout invitation queued for delivery.')
  end

  def verify_payout_sender
    adapter = DymondBank::WorkforcePayouts.new(employer: current_user)
    adapter.verify_sender!
    payout_redirect('Dymond Bank verified access to the configured payout sender.')
  end

  def link_recipient
    fields = params.require(:recipient).permit(:email, :reference)
    disbursements.link_recipient!(partner: partners.find(params[:id]), email: fields[:email], reference: fields[:reference])
    payout_redirect('Verified ACH recipient linked.')
  end

  def prepare_commission
    disbursements.prepare!(referral: referrals.find(params[:id]), order_id: params[:order_id])
    payout_redirect('Dymond Bank payout updated.')
  end

  def release_commission
    payout = find_commission_payout
    outcome = disbursements.release!(payout: payout, review_digest: params[:review_digest],
      proceeds_cleared: params[:proceeds_cleared] == '1')
    if outcome == :quote_changed
      return redirect_to dashboard_sales_partners_path(site_id: @site.id),
        alert: 'The provider quote changed. Review the updated debit before releasing the commission.', status: :see_other
    end

    payout_redirect('Dymond Bank release reviewed. The ledger reflects the provider status.')
  ensure
    queue_reconciliation(payout) if payout
  end

  def refresh_commission
    disbursements.refresh!(payout: find_commission_payout, reference: params[:provider_ref])
    payout_redirect('Dymond Bank payout status refreshed.')
  end

  def record_payout
    fields = params.require(:receipt).permit(:confirmed, :reference, :order_id)
    unless fields[:confirmed] == '1'
      raise ArgumentError, 'Confirm the proceeds cleared and the partner payment completed.'
    end

    @site.with_lock do
      require_site_owner!
      referral = referrals.find(params[:id])
      referral.record_payout!(actor: current_user, reference: fields[:reference], expected_order_id: fields[:order_id])
    end
    redirect_to dashboard_sales_partners_path(site_id: @site.id), notice: 'Commission payment receipt recorded.', status: :see_other
  end

  private

  def referrals
    LightekSales::Referral.where(partner: partners)
  end

  def find_commission_payout
    LightekSales::CommissionPayout.where(referral: referrals, owner: current_user).find(params[:id])
  end

  def disbursements
    LightekSales::CommissionDisbursements.new(actor: current_user, site: @site)
  end

  def queue_reconciliation(payout)
    return unless payout.reload.state.in?(%w[confirming processing])

    LightekSales::CommissionPayoutReconciliationJob.set(wait: 5.minutes).perform_later(payout.id)
  rescue StandardError => error
    Rails.logger.warn("Sales commission reconciliation enqueue failed for payout #{payout.id}: #{error.class}")
  end

  def payout_redirect(notice)
    redirect_to dashboard_sales_partners_path(site_id: @site.id), notice: notice, status: :see_other
  end

  def products
    LightekCommerce::Product.where(site: @site, published: true, product_type: %w[service digital lightek_instance])
  end

  def partners
    LightekSales::Partner.where(site: @site)
  end

  def require_site_owner!
    raise ActiveRecord::RecordNotFound unless @site.tenant_type == 'User' && @site.tenant_id == current_user.id &&
      !current_user.reload.access_suspended_at? && @workspace.revalidate!
  end
end
