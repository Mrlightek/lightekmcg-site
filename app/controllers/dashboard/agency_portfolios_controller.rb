# frozen_string_literal: true

class Dashboard::AgencyPortfoliosController < Dashboard::CommerceBaseController
  protect_from_forgery with: :exception
  before_action :set_site

  def create
    page = LightekDesign::AgencyPortfolio.install!(@site)
    redirect_to preview_dashboard_agency_portfolio_path(site_id: @site.id, slug: page.slug), status: :see_other
  rescue LightekDesign::AgencyPortfolio::Conflict, ActiveRecord::RecordInvalid => error
    redirect_to dashboard_website_designs_path(site_id: @site.id), alert: error.message, status: :see_other
  end

  def preview
    @page = @site.pages.find_by!(slug: params.require(:slug))
    portfolio = LightekDesign::AgencyPortfolio
    @record = @page.sections.where(kind: [portfolio::INDEX_KIND, portfolio::CASE_KIND]).order(:position, :id).first!
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    render :preview, layout: false
  end

  private

  def set_site
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    raise ActiveRecord::RecordNotFound if current_user.role == "client" && @site.tenant != current_user
  end
end
