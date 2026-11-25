# frozen_string_literal: true

class Dashboard::WebsiteWorkspacesController < Dashboard::CommerceBaseController
  protect_from_forgery with: :exception
  before_action :require_workspace_admin!
  before_action :set_website

  rescue_from LightekSettings::WebsiteIdentity::RemovalDenied, with: :redirect_removal_error

  def overview
    visibility = params.require(:visibility)
    raise ActionController::BadRequest unless %w[hidden visible].include?(visibility)

    hidden = visibility == "hidden"
    LightekSettings::WebsiteIdentity.set_overview_hidden!(site: @site, hidden: hidden, request_host: request.host)
    notice = hidden ? "Website hidden from Overview." : "Website restored to Overview."
    redirect_to dashboard_website_settings_path(site_id: @site.id), notice: notice, status: :see_other
  end

  def destroy
    LightekSettings::WebsiteIdentity.delete!(site: @site, confirmation: params[:confirmation], request_host: request.host)
    redirect_to "/dashboard/", notice: "Website deleted.", status: :see_other
  end

  private

  def require_workspace_admin!
    head :forbidden unless current_user&.role == "super_admin"
  end

  def set_website
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
  end

  def redirect_removal_error(error)
    redirect_to dashboard_website_settings_path(site_id: @site.id), alert: error.message, status: :see_other
  end
end
