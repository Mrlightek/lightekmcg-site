# frozen_string_literal: true
class Dashboard::WebsiteSettingsController < Dashboard::SettingsHomeController
  before_action :set_website
  def show; end

  def update
    LightekSettings::WebsiteIdentity.rename!(site: @site, name: params.require(:website).permit(:name).fetch(:name, ""))
    redirect_to dashboard_website_settings_path(site_id: @site.id), notice: "Website name saved."
  rescue ActiveRecord::RecordInvalid => error
    @errors = error.record.errors.full_messages
    render :show, status: :unprocessable_entity
  end

  private
  def set_website
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name, :id)
    @site = if params[:site_id].present?
      @sites.find(params[:site_id])
    else
      @sites.find_by(host: request.host) || (@sites.first if @sites.count == 1)
    end
    raise ActiveRecord::RecordNotFound if action_name == "update" && @site.nil?
  end
end
