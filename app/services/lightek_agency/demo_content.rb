require 'digest'
require 'json'
module LightekAgency
  # Website content only: no users, passwords, provider credentials, billing or
  # financial history cross the installation boundary.
  class DemoContent
    MAX_BYTES = 2.megabytes
    def self.export(demo)
      site = demo.site || raise(Demos::Invalid, 'Demo workspace is unavailable')
      raise Demos::Invalid, 'Demo ownership changed' unless site.tenant == demo.client
      pages = site.pages.order(:position, :id).limit(101).to_a
      raise Demos::Invalid, 'Demo export supports up to 100 pages' if pages.size > 100
      content = {'version' => 1, 'demo_id' => demo.public_id, 'name' => site.name, 'design' => export_design(site), 'pages' => pages.map do |page|
        sections = page.sections.order(:position, :id).limit(101).to_a
        raise Demos::Invalid, 'Demo export supports up to 100 sections per page' if sections.size > 100
        raise Demos::Invalid, 'Custom Studio sections cannot be promoted yet. Use standard website sections before checkout.' if sections.any? { |section| section.kind.to_s.start_with?('ld_') }
        page.attributes.slice('title', 'slug', 'published', 'position').merge('sections' => sections.map { |section| section.attributes.slice('kind', 'position', 'data') })
      end}
      raise Demos::Invalid, 'Demo website exceeds the 2 MB upgrade snapshot limit' if JSON.generate(content).bytesize > MAX_BYTES
      content
    end
    def self.export_design(site)
      return unless site.respond_to?(:active_template) && site.active_template
      settings = site.active_template.settings.to_h
      design = settings['lightek_design']
      raise Demos::Invalid, 'Custom Studio designs cannot be promoted yet. Choose a built-in design before checkout.' unless design.present? && LightekDesign::Catalog.designs.key?(design)
      {'key' => design, 'tokens' => settings.fetch('tokens', {})}
    end
    def self.digest(content) = Digest::SHA256.hexdigest(JSON.generate(content.deep_stringify_keys))
    def self.install!(site:, content:)
      content = content.deep_stringify_keys
      raise ArgumentError, 'Invalid demo content version' unless content['version'] == 1
      raise ArgumentError, 'Demo content is too large' if JSON.generate(content).bytesize > MAX_BYTES
      digest = digest(content)
      site.with_lock do
        previous = site.manifest.to_h['demo_content_digest']
        return digest if previous == digest
        raise ArgumentError, 'An existing demo import must not be replaced' if previous.present?
        raise ArgumentError, 'Only a fresh installation can import demo content' unless site.manifest.to_h['lightek_website_bootstrap']
        pages = content.fetch('pages')
        raise ArgumentError, 'Invalid demo page count' unless pages.is_a?(Array) && pages.size.between?(1, 100)
        # Bootstrap owns the initial homepage. Import runs inside bootstrap's
        # transaction before the owner can use the newly provisioned instance.
        if content['design'].present?
          design = content.fetch('design')
          template = LightekDesign::WebsiteDesigns.template_for!(site: site, design: design.fetch('key'))
          template.update!(settings: template.settings.merge('tokens' => design.fetch('tokens', {})))
          site.update!(active_template: template)
        end
        site.nav_menu&.nav_items&.destroy_all
        site.pages.each { |page| page.sections.destroy_all; page.destroy! }
        pages.each do |data|
          raise ArgumentError, 'Invalid demo section count' unless data.fetch('sections').is_a?(Array) && data['sections'].size <= 100
          page = site.pages.create!(data.slice('title', 'slug', 'published', 'position'))
          data['sections'].each { |section| page.sections.create!(section.slice('kind', 'position', 'data')) }
        end
        # There must be a public homepage for the existing deployment verifier.
        home = site.pages.find_by!(slug: 'home')
        home.update!(published: true)
        raise ArgumentError, 'A demo homepage needs content' unless home.sections.exists?
        site.update!(name: content.fetch('name'), manifest: site.manifest.to_h.merge('demo_content_digest' => digest))
        if site.nav_menu
          site.pages.where(published: true).order(:position).each do |page|
            site.nav_menu.nav_items.create!(page: page, label: page.title, position: page.position)
          end
        end
      end
      digest
    end
  end
end
