# A theme coordinates existing editable pages, chrome and navigation. It never
# executes uploaded scripts or replaces commerce, identity or publishing services.
module LightekDesign
  class SiteTheme
    KEY = "lightek_site_theme"
    def self.current(site) = site&.active_template&.settings.to_h[KEY]
    def self.authorize!(site, user)
      raise ActiveRecord::RecordNotFound unless user && LightekSettings::WebsiteIdentity.sites_for(user).exists?(id: site.id)
    end
    def self.install!(site:, user:, name:, files:, request_key:, css_file: nil, home_file: nil, product_selector: nil)
      authorize!(site,user)
      raise ArgumentError,"Name this website theme (1–120 characters)." unless name.to_s.strip.length.between?(1,120)
      raise ArgumentError,"A valid installation key is required." unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
      files=Array(files).reject(&:blank?)
      raise ArgumentError,"Choose 1–10 HTML pages for this website." unless files.length.between?(1,10)
      names=files.map{|f|File.basename(f.original_filename.to_s)}
      raise ArgumentError,"Each HTML file must have a different filename." unless names.uniq.size==names.size
      home=home_file.to_s.presence || names.find{|n|n.match?(/\A(?:index|home)\.html?\z/i)} || names.first
      raise ArgumentError,"The home filename must match an uploaded HTML file." unless names.include?(home)
      css=css_file.present? ? HtmlImport.read_file!(css_file,%w[.css]) : ""
      documents=files.map do |file|
        filename=File.basename(file.original_filename.to_s)
        role=filename==home ? "home" : filename.match?(/store|shop/i) ? "store" : filename.match?(/blog|journal/i) ? "blog" : "page"
        source=HtmlImport.read_file!(file,%w[.html .htm])
        original_source=source
        parsed=Nokogiri::HTML5.parse(source)
        main=parsed.at_css('main')
        if !%w[store blog].include?(role) && parsed.at_css('script') && main && main.text.strip.blank? && !main.at_css('img,video,audio')
          raise ArgumentError,"#{filename} generates its main content in JavaScript. Export visible HTML or connect a native application section before installing this page."
        end
        # Store and journal are application surfaces, not mock product/post data.
        selector=role=="store" ? product_selector.presence || (Nokogiri::HTML5.parse(source).at_css('[data-lightek-products]') ? '[data-lightek-products]' : '#grid') : nil
        if role=='store'
          parsed.css('button[data-f],aside[aria-label="Cart"],aside[aria-label="Product details"],#ov').each(&:remove)
          source=parsed.to_html
        end
        document,warnings=HtmlDocument.convert(html:source,css:css,name:File.basename(filename,'.html').tr('_',' ').humanize,
          product_selector:selector,blog_selector:role=="blog" ? "main" : nil)
        {filename:filename,role:role,document:document,warnings:warnings,source:original_source}
      end
      site.with_lock do
        existing=site.manifest.to_h.fetch("lightek_site_themes",{})[request_key]
        return DymondSite::SiteTemplate.find(existing) if existing
        pages=documents.map do |item|
          workspace=StudioDocument.create!(user:user,name:item[:document]["name"])
          release=StudioDocument.publish!(record:workspace,document:item[:document],expected_revision:StudioDocument.revision(workspace))
          page=WebsiteDesigns.import!(site:site,design:release.key)
          base=item[:role]=="home" ? "home" : File.basename(item[:filename],File.extname(item[:filename])).parameterize.presence || "page"
          slug=base;index=2
          while site.pages.where.not(id:page.id).exists?(slug:slug);slug="#{base}-#{index}";index+=1;end
          page.update!(title:item[:document]["name"],slug:slug)
          {"page_id"=>page.id,"design"=>release.key,"filename"=>item[:filename],"role"=>item[:role],"slug"=>slug,"warnings"=>item[:warnings]}
        end
        save_bundle!(site:site,name:name,pages:pages,request_key:request_key,source_files:documents.to_h{|d|[d[:filename],d[:source]]})
      end
    end
    def self.from_designs!(site:,user:,name:,home_design:,page_designs:[],include_store:false,include_blog:false,request_key:)
      authorize!(site,user)
      raise ArgumentError,"Name this website theme (1–120 characters)." unless name.to_s.strip.length.between?(1,120)
      raise ArgumentError,"A valid installation key is required." unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
      keys=([home_design.to_s]+Array(page_designs).reject(&:blank?)).uniq
      raise ArgumentError,"Choose a home design and at most seven additional page designs." unless keys.size.between?(1,8) && keys.first.present?
      allowed=Catalog.selectable_designs(user:user,active:Catalog.design_for(site))
      definitions=keys.to_h{|key|[key,allowed.fetch(key){raise ActiveRecord::RecordNotFound}]}
      site.with_lock do
        existing=site.manifest.to_h.fetch("lightek_site_themes",{})[request_key]
        return DymondSite::SiteTemplate.find(existing) if existing
        pages=keys.map.with_index do |key,index|
          page=WebsiteDesigns.import!(site:site,design:key)
          {"page_id"=>page.id,"design"=>key,"filename"=>"#{page.slug}.html","role"=>index.zero? ? "home" : "page","slug"=>page.slug,"warnings"=>[]}
        end
        {"store"=>include_store,"blog"=>include_blog}.each do |role,enabled|
          next unless enabled
          document=StudioDocument.from_definition(definitions.fetch(keys.first))
          document["name"]=role=="store" ? "Store" : "Journal"
          chrome=document["sections"].select{|section|section["chrome_header"]||section["chrome_footer"]}
          source=role=="store" ? CommerceSections.definitions.first : ContentSections.definitions.first
          live={"id"=>SecureRandom.hex(6),"title"=>document["name"],"anchor"=>role,"source_kind"=>source["kind"],"data"=>source["data"].deep_dup,"style"=>StudioDocument::STYLE_DEFAULTS.deep_dup}
          document["sections"]=chrome.select{|section|section["chrome_header"]}+[live]+chrome.reject{|section|section["chrome_header"]}
          workspace=StudioDocument.create!(user:user,name:document["name"])
          release=StudioDocument.publish!(record:workspace,document:document,expected_revision:StudioDocument.revision(workspace))
          page=WebsiteDesigns.import!(site:site,design:release.key)
          pages<<{"page_id"=>page.id,"design"=>release.key,"filename"=>"#{role}.html","role"=>role,"slug"=>page.slug,"warnings"=>[]}
        end
        save_bundle!(site:site,name:name,pages:pages,request_key:request_key)
      end
    end
    def self.save_bundle!(site:,name:,pages:,request_key:,source_files:{})
      home=pages.find{|page|page["role"]=="home"}
      base=WebsiteDesigns.template_for!(site:site,design:home.fetch("design"))
      chrome=Catalog.fetch(home.fetch("design")).fetch("sections").select{|section|section["chrome_header"]||section["chrome_footer"]}
      metadata={"site_id"=>site.id,"pages"=>pages,"chrome_page_id"=>home.fetch("page_id"),"chrome"=>chrome}
      if source_files.present?
        source=DymondSite::SiteTemplate.create!(key:"ld_html_theme_source_#{site.id}_#{SecureRandom.hex(10)}",name:"#{name.strip} source",settings:{"lightek_site_id"=>site.id,"lightek_theme_source"=>{"site_id"=>site.id,"files"=>source_files}})
        metadata["source_record_id"]=source.id
      end
      template=DymondSite::SiteTemplate.create!(key:"lightek_theme_#{site.id}_#{SecureRandom.hex(10)}",name:name.strip,description:"Coordinated website theme",
        settings:base.settings.except(KEY).merge(KEY=>metadata))
      manifest=site.manifest.to_h.deep_dup
      manifest["lightek_site_themes"]=manifest.fetch("lightek_site_themes",{}).merge(request_key=>template.id)
      site.update!(manifest:manifest)
      template
    end
    private_class_method :save_bundle!
    def self.activate!(site:, user:, template_id:)
      authorize!(site,user)
      site.with_lock do
        template=DymondSite::SiteTemplate.find(template_id)
        theme=template.settings.fetch(KEY)
        raise ActiveRecord::RecordNotFound unless theme["site_id"].to_s==site.id.to_s
        menu=site.nav_menu || site.create_nav_menu!(name:"Main Menu")
        theme.fetch("pages").each do |entry|
          page=site.pages.find(entry.fetch("page_id"))
          unless menu.nav_items.exists?(page_id:page.id)
            menu.nav_items.create!(page:page,label:page.title,position:menu.nav_items.maximum(:position).to_i+1)
          end
        end
        manifest=site.manifest.to_h.deep_dup
        if (shop=theme["pages"].find{|p|p["role"]=="store"})
          manifest.merge!("lightek_commerce_starter_page_id"=>shop["page_id"],"lightek_commerce_design_key"=>shop["design"])
          manifest["lightek_commerce_design_pages"]=manifest.fetch("lightek_commerce_design_pages",{}).merge(shop["page_id"].to_s=>shop["design"])
        end
        site.update!(active_template:template,manifest:manifest)
      end
      site
    rescue KeyError
      raise ActiveRecord::RecordNotFound
    end
    def self.page_url(site,entry)
      return "/commerce/shop?site_id=#{site.id}" if entry["role"]=="store"
      return "/blog" if entry["role"]=="blog"
      page=site.pages.find_by(id:entry["page_id"])
      page&.published? ? (page.slug=="home" ? "/" : "/site/#{page.slug}") : nil
    end
  end
end
