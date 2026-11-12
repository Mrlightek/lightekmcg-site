class Dashboard::CustomersController < Dashboard::CommerceBaseController
  before_action :set_site
  def index
    scope = LightekCommerce::Order.where(site: @site).where.not(paid_at: nil)
    if params[:q].present?
      scope = scope.where("customer_email ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(160))}%")
    end
    @customers = scope.group(:customer_email).select("customer_email, COUNT(*) AS order_count, SUM(total_cents - refunded_cents) AS collected_cents, MAX(paid_at) AS last_purchase_at").order("MAX(paid_at) DESC").limit(200)
  end
  def history
    @email = params.require(:email).to_s.downcase
    @orders = LightekCommerce::Order.where(site: @site, customer_email: @email).includes(:items).order(id: :desc).limit(100)
    @contact = LightekMarketing::Contact.find_by(site: @site, email: @email)
  end
  private
  def set_site
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first!
  end
end
