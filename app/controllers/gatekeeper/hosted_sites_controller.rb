module Gatekeeper
  class HostedSitesController < ApplicationController
    allow_unauthenticated_access only: %i[show health]
    helper DymondDash::TemplateSchemaHelper
    helper LightekDesign::StudioHelper
    before_action :load_site

    def show
      @page = params[:slug].present? ? @site.pages.published.find_by!(slug: params[:slug]) : @site.home_page
      raise ActiveRecord::RecordNotFound unless @page&.published?
      render "lightek_design/page", layout: "lightek_design/website"
    end

    def health
      response.headers["Cache-Control"] = "no-store"
      page = @site.home_page
      return head :service_unavailable unless page&.published? && page.sections.exists?
      render json: {site_id: @site.id, domain: @site.host, application_key: @site.manifest.fetch("hosted_application_key")}
    end

    private

    def load_site
      @site = DymondSite::Site.find_by!(host: request.host.downcase)
      raise ActiveRecord::RecordNotFound if @site.manifest.to_h["hosted_application_key"].blank?
    end
  end
end
