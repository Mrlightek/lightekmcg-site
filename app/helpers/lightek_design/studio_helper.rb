# frozen_string_literal: true
module LightekDesign
  module StudioHelper
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
