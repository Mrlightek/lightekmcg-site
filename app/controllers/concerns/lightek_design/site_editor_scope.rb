# frozen_string_literal: true
module LightekDesign
  module SiteEditorScope
    private

    def set_site
      sites = LightekSettings::WebsiteIdentity.sites_for(current_user)
      selected = params[:site_id].presence || session[:dymond_dash_site_id]
      @site = selected ? sites.find(selected) : (sites.first if sites.count == 1)
      unless @site
        redirect_to main_app.dashboard_website_designs_path, alert: "Choose a website first."
        return
      end
      session[:dymond_dash_site_id] = @site.id
    end
  end
end
