# frozen_string_literal: true

module LightekDesign
  module AgencyPortfolio
    INDEX_KIND = "lightek_portfolio_index"
    CASE_KIND = "lightek_portfolio_case"
    INDEX_SLUG = "work"
    MAX_PROJECTS = 80

    INDEX_DATA = {
      "heading" => "Work with a point of view.",
      "intro" => "Websites, brand identities and print designed to make good ideas stand out."
    }.freeze

    CASE_FIELDS = {
      "category" => "Category", "summary" => "Project summary", "cover_url" => "Cover image URL",
      "cover_alt" => "Cover image description", "featured" => "Featured project (yes or no)",
      "sample" => "Concept project (yes or no)",
      "challenge" => "The brief", "approach" => "The approach", "outcome" => "The outcome",
      "gallery_1_url" => "Gallery image 1 URL", "gallery_1_alt" => "Gallery image 1 description",
      "gallery_2_url" => "Gallery image 2 URL", "gallery_2_alt" => "Gallery image 2 description",
      "project_url" => "Live project URL"
    }.freeze

    EXAMPLES = [
      {
        slug: "work-studio-current", title: "Studio Current", category: "Websites", featured: "yes",
        summary: "A website concept for a small business ready to make a bigger first impression.",
        challenge: "Make a broad set of services feel clear and focused from the first visit.",
        approach: "Build a short path from the homepage to a relevant service, supporting work and a consultation.",
        outcome: "A responsive design concept with clearer service pages and a dedicated consultation path.",
        cover_alt: "Cobalt blue design toolkit photographed against a deep indigo backdrop"
      },
      {
        slug: "work-first-light", title: "First Light", category: "Book covers",
        summary: "An editorial cover concept built around the first rays of a sunrise.",
        challenge: "Give an independent book a cover that reads as well at thumbnail size as it does in print.",
        approach: "Use bold geometry and a restrained palette to give the book a clear, recognizable silhouette.",
        outcome: "A book jacket concept with coordinated front, spine and back treatments.",
        cover_alt: "Coral book cover mockup with geometric sunrise artwork"
      },
      {
        slug: "work-field-note", title: "Field Note", category: "Branding & print",
        summary: "A tactile identity concept for a business that wants to feel personal and established.",
        challenge: "Create a brand identity that holds together across small print pieces and digital applications.",
        approach: "Pair an earthy palette with straightforward typography and tactile paper stock.",
        outcome: "An identity concept shown across stationery and business cards.",
        cover_alt: "Moss green stationery and cream business cards beside a green glass object"
      }
    ].freeze

    class Conflict < StandardError; end

    module_function

    def definitions
      index_fields = {"heading" => "Headline", "intro" => "Introduction",
        "cta_label" => "Consultation button label", "cta_url" => "Consultation or proposal URL"}
      [
        {"kind" => INDEX_KIND, "fields" => fields(index_fields), "data" => INDEX_DATA.dup},
        {"kind" => CASE_KIND, "fields" => fields(CASE_FIELDS), "data" => {}}
      ]
    end

    def fields(labels)
      labels.map do |name, label|
        {"name" => name, "label" => label,
          "type" => %w[intro summary challenge approach outcome].include?(name) ? "textarea" : "text"}
      end
    end

    def install!(site)
      site.with_lock do
        existing = index_page(site: site, draft: true)
        return existing if existing
        if site.pages.exists?(slug: INDEX_SLUG)
          raise Conflict, "This website already has a Work page. Add a Portfolio Index section there in Pages & Sections."
        end

        conflicts = site.pages.where(slug: EXAMPLES.pluck(:slug)).exists?
        raise Conflict, "A portfolio sample URL already exists. Choose a different page slug before installing." if conflicts

        position = (site.pages.maximum(:position) || -1) + 1
        index = site.pages.create!(slug: INDEX_SLUG, title: "Selected work", position: position, published: false)
        index.sections.create!(kind: INDEX_KIND, position: 0, data: INDEX_DATA)
        EXAMPLES.each_with_index do |example, i|
          page = site.pages.create!(slug: example.fetch(:slug), title: example.fetch(:title),
            position: position + i + 1, published: false)
          data = example.except(:slug, :title).stringify_keys.merge(
            "cover_url" => "/lightek/portfolio-art.webp", "sample_art" => (i + 1).to_s,
            "sample" => "yes")
          page.sections.create!(kind: CASE_KIND, position: 0, data: data)
        end
        index
      end
    end

    def section_pages(site:, kind:, draft:)
      scope = site.pages
      scope = scope.where(published: true) unless draft
      sections = DymondSite::Section.where(kind: kind)
      scope.where(id: sections.select(:page_id))
    end

    def index_page(site:, draft: false)
      section_pages(site: site, kind: INDEX_KIND, draft: draft).order(:position, :id).first
    end

    def projects(site:, draft: false)
      selected = section_pages(site: site, kind: CASE_KIND, draft: draft).order(:position, :id).limit(MAX_PROJECTS).to_a
      data_by_page = DymondSite::Section.where(page_id: selected.map(&:id), kind: CASE_KIND)
        .order(:position, :id).group_by(&:page_id)
      selected.map do |page|
        data = data_by_page.fetch(page.id, []).first&.data.to_h
        {page: page, data: data, category: data["category"].to_s.strip.presence || "Other"}
      end.partition { |project| enabled?(project[:data]["featured"]) }.flatten(1)
    end

    def enabled?(value)
      %w[yes true 1].include?(value.to_s.strip.downcase)
    end

    def sample_art(data)
      data["sample_art"] if data["cover_url"] == "/lightek/portfolio-art.webp" && %w[1 2 3].include?(data["sample_art"])
    end

    def gallery_images(data)
      [1, 2].filter_map do |position|
        source = url(data["gallery_#{position}_url"], image: true)
        [source, data["gallery_#{position}_alt"].to_s] if source
      end
    end

    def url(value, image: false)
      result = Catalog.safe_url(value, image: image)
      result unless result == "#"
    end

    def path(page, site:, draft: false)
      return "/site/#{ERB::Util.url_encode(page.slug)}" unless draft

      Rails.application.routes.url_helpers.preview_dashboard_agency_portfolio_path(site_id: site.id, slug: page.slug)
    end
  end
end
