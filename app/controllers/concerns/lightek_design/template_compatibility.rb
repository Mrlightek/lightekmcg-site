# frozen_string_literal: true
module LightekDesign
  module TemplateCompatibility
    def index
      super
      @templates = @templates.reject do |template|
        owner = template.settings["lightek_site_id"]
        owner.present? && owner.to_s != @site.id.to_s
      end
    end

    def apply
      template = DymondSite::SiteTemplate.find(params[:id])
      design = template.settings["lightek_design"]
      return super unless Catalog.designs.key?(design)
      WebsiteDesigns.apply!(site: @site, design: design)
      redirect_to main_app.dashboard_website_designs_path(site_id: @site.id), notice: "Website design applied."
    end

    private

    def set_template
      super
      owner = @template.settings["lightek_site_id"]
      raise ActiveRecord::RecordNotFound if owner.present? && owner.to_s != @site.id.to_s
    end

    def template_params
      values = super
      if @template && @template.settings["lightek_design"].present?
        values["settings"] = @template.settings.merge(values.fetch("settings"))
      end
      values
    end
  end
end
