# frozen_string_literal: true
module LightekCommerce
  module IndustryStarters
    INDUSTRIES = {
      "retail" => {name: "Retail & Boutique", heading: "Everyday pieces. Uncommon style.", intro: "A considered collection for the way you live.", accent: "#b45309", background: "#fffaf2", ink: "#282119", categories: ["The new collection", "Everyday essentials", "Finishing touches"], story: "Good design belongs in your everyday.", detail: "Introduce the people, materials and ideas behind your collection.", motif: "The seasonal edit"},
      "beauty" => {name: "Beauty & Wellness", heading: "A little ritual. A lot of you.", intro: "Make room for your next favorite daily ritual.", accent: "#9d3563", background: "#fff5f7", ink: "#38262f", categories: ["Daily care", "Rest & reset", "The finishing touch"], story: "Care starts with intention.", detail: "Share your approach to ingredients, routines and personal care.", motif: "Your daily ritual"},
      "food" => {name: "Food & Hospitality", heading: "Something delicious starts here.", intro: "Find your next favorite flavor, made for your table.", accent: "#a13e21", background: "#fff8ed", ink: "#33271f", categories: ["From the kitchen", "For the table", "Share something good"], story: "From our kitchen to your table.", detail: "Tell the story behind your menu, your makers and your flavors.", motif: "Fresh from the kitchen"},
      "creators" => {name: "Artists & Creators", heading: "Original work. Yours to own.", intro: "Discover the latest releases and support the work behind them.", accent: "#b9f655", background: "#15151b", ink: "#f4f1ff", categories: ["Latest releases", "Wear the work", "From the archive"], story: "Meet the mind behind the work.", detail: "Introduce your practice, inspirations and the story of this collection.", motif: "The latest drop"},
      "services" => {name: "Professional Services", heading: "Your next chapter starts here.", intro: "Explore focused services built around your goals.", accent: "#285bca", background: "#f3f6fc", ink: "#18263f", categories: ["Get started", "Build momentum", "Work together"], story: "A partner for what comes next.", detail: "Explain your process, your expertise and how a client can begin.", motif: "Built around your goals"}
    }.freeze

    def self.document(industry, site:)
      config = INDUSTRIES.fetch(industry.to_s)
      block = lambda do |key, title, data, background: config[:background], color: config[:ink]|
        LightekDesign::StudioDocument.new_block(key).merge("title" => title, "anchor" => "", "data" => data,
          "style" => LightekDesign::StudioDocument::STYLE_DEFAULTS.merge("background" => background, "color" => color, "padding" => 72, "radius" => 20))
      end
      hero = block.call("hero", "Shop introduction", {"eyebrow" => "#{site.name} / #{config[:motif]}", "heading" => config[:heading], "body" => config[:intro], "cta_label" => "Explore the collection", "cta_url" => "#products", "image_url" => "/lightek/commerce/#{industry}.svg", "image_alt" => "#{config[:name]} collection illustration"})
      hero["anchor"] = "shop-home"
      collections = block.call("cards", "Collection highlights", {"heading" => "Find your inspiration", "body" => "Explore what speaks to you.", "items" => config[:categories].map { |name| {"title" => name, "body" => "Explore the collection.", "url" => "#products"} }})
      product_style = LightekDesign::StudioDocument::STYLE_DEFAULTS.merge("background" => config[:background], "color" => config[:ink], "padding" => 64)
      products = {"id" => SecureRandom.hex(6), "anchor" => "products", "title" => "Live shop products", "source_kind" => "lightek_product_grid", "data" => {"heading" => "Explore #{site.name}", "intro" => config[:intro]}, "style" => product_style}
      story = block.call("split", "Brand story", {"eyebrow" => "Behind the collection", "heading" => config[:story], "body" => config[:detail], "image_url" => "/lightek/commerce/#{industry}.svg", "image_alt" => "#{config[:name]} design detail", "cta_label" => "Shop the collection", "cta_url" => "#products"})
      cta = block.call("cta", "Shopping & checkout", {"heading" => "Find your next favorite.", "body" => "Explore the collection, add your choices to the cart and continue to secure checkout.", "cta_label" => "View cart & checkout", "cta_url" => "/commerce/shop?site_id=#{site.id}#cart"})
      footer = block.call("footer", "Shop footer", {"heading" => site.name, "body" => "#{site.name} · #{config[:motif]}", "cta_label" => "Back to collection", "cta_url" => "#products"})
      {"name" => "#{config[:name]} · #{site.name}", "description" => "Complete editable shop design with a live product collection, brand story and secure cart.", "base_design" => "plain",
        "tokens" => {"color_bg" => config[:background], "color_text" => config[:ink], "color_primary" => config[:accent], "color_text_muted" => config[:ink]},
        "fonts" => {"font_sans" => "Inter", "font_heading" => industry.to_s == "creators" ? "Space Grotesk" : "DM Sans", "font_mono" => "DM Mono"}, "sections" => [hero, collections, products, story, cta, footer]}
    end

    def self.install!(site:, industry:, user:)
      INDUSTRIES.fetch(industry.to_s)
      site.with_lock do
        manifest = site.manifest.to_h.deep_dup
        imports = manifest.fetch("lightek_industry_pages", {})
        if (saved = imports[industry.to_s]) && (page = site.pages.find_by(id: saved["page_id"]))
          site.update!(manifest: site.manifest.to_h.merge("lightek_commerce_starter_page_id" => page.id, "lightek_commerce_design_key" => saved["release_key"]))
          next page
        end
        document = document(industry, site: site)
        workspace = LightekDesign::StudioDocument.create!(user: user, name: document["name"])
        release = LightekDesign::StudioDocument.publish!(record: workspace, document: document, expected_revision: 1)
        page = LightekDesign::WebsiteDesigns.import!(site: site, design: release.key)
        page.update!(title: "#{INDUSTRIES[industry.to_s][:name]} Shop")
        imports[industry.to_s] = {"page_id" => page.id, "release_key" => release.key, "document_id" => workspace.id}
        candidates = site.manifest.to_h.fetch("lightek_commerce_design_pages", {}).merge(page.id.to_s => release.key)
        site.update!(manifest: site.manifest.to_h.merge("lightek_commerce_design_pages" => candidates, "lightek_industry_pages" => imports, "lightek_commerce_starter_page_id" => page.id, "lightek_commerce_design_key" => release.key))
        page
      end
    end
  end
end
