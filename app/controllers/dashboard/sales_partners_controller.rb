# frozen_string_literal: true

class Dashboard::SalesPartnersController < Dashboard::SalesController
  skip_before_action :set_kind
  before_action :require_site_owner!, except: :materials
  helper NevaehHelpHelper

  rescue_from ActiveRecord::RecordInvalid do |error|
    redirect_to dashboard_sales_partners_path(site_id: @site.id), alert: error.record.errors.full_messages.to_sentence
  end
  rescue_from ArgumentError do |error|
    redirect_to dashboard_sales_partners_path(site_id: @site.id), alert: error.message
  end

  def materials
    @tab = 'materials'
    @kit = Rails.root.join('docs/sales/managed-website-sales-kit.md').read
  end

  def index
    @tab = 'partners'
    @products = products.order(:name)
    @partners = partners.includes(:product).order(:revoked_at, :name)
    @referrals = LightekSales::Referral.where(partner: partners).includes(:partner, lead: :opportunity)
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

  def record_payout
    fields = params.require(:receipt).permit(:confirmed, :reference, :order_id)
    unless fields[:confirmed] == '1'
      raise ArgumentError, 'Confirm the proceeds cleared and the partner payment completed.'
    end

    @site.with_lock do
      require_site_owner!
      referral = LightekSales::Referral.where(partner: partners).find(params[:id])
      referral.record_payout!(actor: current_user, reference: fields[:reference], expected_order_id: fields[:order_id])
    end
    redirect_to dashboard_sales_partners_path(site_id: @site.id), notice: 'Commission payment receipt recorded.', status: :see_other
  end

  private

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
