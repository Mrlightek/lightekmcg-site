module LightekDesign
  class HtmlBindings
    def self.render(source, site:, navigation_html: nil)
      html=HtmlDocument.render_html(source)
      return html unless site
      fragment=Nokogiri::HTML5.fragment(html)
      theme=SiteTheme.current(site)
      pages=theme.to_h.fetch("pages",[])
      routes={"site"=>"/","home"=>"/","blog"=>"/blog","journal"=>"/blog","store"=>"/commerce/shop?site_id=#{site.id}","shop"=>"/commerce/shop?site_id=#{site.id}","cart"=>"/commerce/shop?site_id=#{site.id}#lightek-cart","members"=>"/lightek/index.html"}
      pages.each do |entry|
        url=SiteTheme.page_url(site,entry)
        next unless url
        routes[entry["filename"]]=url
        basename=File.basename(entry["filename"],File.extname(entry["filename"]))
        routes[basename]=url
        routes[basename.split('_').last]=url
      end
      fragment.css("a").each do |link|
        key=link["data-lightek-route"].presence || link["data-l"].presence || link["href"]
        base,separator,fragment_id=key.to_s.partition('#')
        next unless routes[key] || routes[base]
        target=routes[key] || routes[base]
        target+="##{fragment_id}" if separator.present? && fragment_id.match?(/\A[a-zA-Z][\w-]*\z/)

        hash=link["data-h"].to_s
        if hash.match?(/\A#[a-zA-Z][\w-]*\z/)
          target = %w[blog journal].include?(key) ? "/blog/#{hash.delete_prefix('#')}" : target+hash unless target.include?('#')
        end
        link["href"]=target
        link.remove_attribute("target")
      end
      if theme && navigation_html
        fragment.css('header button').each{|button|button.remove if button['aria-controls'].present? || button['aria-label'].to_s.match?(/menu/i) || button['class'].to_s.match?(/ham|burger|menu/)}
        fragment.css('header nav,[data-lightek-navigation]').each { |nav| nav.inner_html=navigation_html }
      end
      HtmlDocument.clean_html(fragment.to_html)
    end
  end
end
