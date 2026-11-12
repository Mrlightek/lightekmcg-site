# frozen_string_literal: true
module LightekDesign
  module StudioHelper
    def studio_navigation_current?(url)
      target=url.to_s.split('?').first
      request.path==target || (target=='/' && request.path=='/site/home') || (target=='/blog' && request.path.start_with?('/blog/'))
    end
    def studio_navigation_href(item)
      entry=LightekDesign::SiteTheme.current(@site).to_h.fetch("pages",[]).find{|page|page["page_id"].to_s==item.page_id.to_s} if item.page_id
      entry ? (LightekDesign::SiteTheme.page_url(@site,entry) || "#") : LightekDesign::Catalog.safe_url(item.href)
    end
    def studio_theme_chrome(kind)
      theme=LightekDesign::SiteTheme.current(@site).to_h
      entry=theme.fetch("chrome", []).find { |section| section["chrome_#{kind}"] }
      if entry && theme["chrome_page_id"]
        record=@site.pages.find_by(id:theme["chrome_page_id"])&.sections&.find_by(kind:entry["kind"])
        entry=entry.merge("data"=>record.data) if record
      end
      entry
    end
    def studio_theme_section?(entry)
      entry && ((entry["chrome_header"] && studio_theme_chrome("header")) || (entry["chrome_footer"] && studio_theme_chrome("footer")))
    end
    def studio_bound_html(source)
      navigation = if !@preview && LightekDesign::SiteTheme.current(@site) && @site.nav_menu
        @_studio_bound_navigation ||= render("lightek_design/bound_navigation", site: @site)
      end
      @preview ? LightekDesign::HtmlDocument.render_html(source) : LightekDesign::HtmlBindings.render(source, site: @site, navigation_html: navigation)
    end
    def studio_render_section(entry, data)
      render "lightek_design/designer/section", entry: entry, section_data: data
    end
    def studio_section_style(entry)
      style = StudioDocument.normalize_style(entry["style"] || {})
      {"padding" => "#{style['padding']}px", "width" => "#{style['width']}px", "gap" => "#{style['gap']}px", "columns" => style["columns"], "radius" => "#{style['radius']}px", "heading-size" => "#{style['heading_size']}px", "align" => style["align"], "bg" => style["background"], "text" => style["color"]}.map { |key, value| "--ld-#{key}:#{value}" }.join(";")
    end
    def studio_original_partial(entry)
      kind = entry.fetch("render_kind")
      if Catalog.builtin_designs.values.any? { |definition| definition["sections"].any? { |section| section["kind"] == kind } }
        "lightek_design/sections/#{kind}"
      else
        "dymond_site/themes/default/sections/#{kind}"
      end
    end
  end
end
