# frozen_string_literal: true
module LightekDesign
  module PublicWebsite
    # Let each controller keep its existing lookup, host rejection and publishing
    # rules. Intercept the view only after those rules have selected a real page.
    def render(*args, **options, &block)
      if response.status.to_i < 400 && !options.key?(:status) && lightek_public_design_page?
        return super(template: "lightek_design/page", layout: "lightek_design/website")
      end
      super
    end

    def default_render
      if lightek_public_design_page?
        render template: "lightek_design/page", layout: "lightek_design/website"
      else
        super
      end
    end

    private

    def lightek_public_design_page?
      return false unless action_name == "show" && @site && @page&.published?
      return true if Catalog.active?(@site)

      @design_key = WebsiteDesigns.imported_release_key(site: @site, page: @page)
      @design_key.present?
    end
  end
end
