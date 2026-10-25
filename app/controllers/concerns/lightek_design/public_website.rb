# frozen_string_literal: true
module LightekDesign
  module PublicWebsite
    # Let each controller keep its existing lookup, host rejection and publishing
    # rules. Intercept the view only after those rules have selected a real page.
    def render(*args, **options, &block)
      if action_name == "show" && @site && @page && @page.published? && Catalog.active?(@site) && response.status.to_i < 400 && !options.key?(:status)
        return super(template: "lightek_design/page", layout: "lightek_design/website")
      end
      super
    end

    def default_render
      if action_name == "show" && @site && @page && @page.published? && Catalog.active?(@site)
        render template: "lightek_design/page", layout: "lightek_design/website"
      else
        super
      end
    end
  end
end
