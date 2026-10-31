# frozen_string_literal: true
class Dashboard::AuthenticationBrandingController < Dashboard::SettingsHomeController
  before_action :set_site
  protect_from_forgery with: :exception
  def edit
    @branding = LightekDesign::AuthenticationBranding.new(@site)
    response.headers["Cache-Control"] = "no-store, private"
  end
  def update
    values = params.require(:branding).permit(*LightekDesign::AuthenticationBranding::TEXT_KEYS,
      *LightekDesign::AuthenticationBranding::COLORS, *LightekDesign::AuthenticationBranding::FONTS, :remove_logo, :remove_background).to_h
    LightekDesign::AuthenticationBranding.save!(site: @site, values: values, logo: params[:logo], background: params[:background])
    redirect_to dashboard_authentication_branding_path(site_id: @site.id), notice: "Account branding saved. Sign-in, registration and password screens now use your website identity.", status: :see_other
  rescue ArgumentError => error
    @branding = LightekDesign::AuthenticationBranding.new(@site)
    flash.now[:alert] = error.message
    render :edit, status: :unprocessable_entity
  end
  private
  def set_site
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
  end
end
