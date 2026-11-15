module LightekGrowth
  module Audits
    class Renderer
      def self.call(page)
        raise ArgumentError, 'This audit currently supports the active Lightek website layout.' unless LightekDesign::Catalog.active?(page.site)
        html = AuditPagesController.renderer.new(http_host: page.site.host, https: true).render(template: 'lightek_design/page', layout: 'lightek_design/website', assigns: {site: page.site, page: page})
        raise Source::Limit, 'Rendered page exceeds 1 MB.' if html.bytesize > 1_000_000
        html
      end
    end
  end
end
