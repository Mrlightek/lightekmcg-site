require 'digest'
require 'json'
module LightekGrowth
  module Audits
    module Source
      class Limit < StandardError; end
      module_function
      def canonical(value)
        case value
        when Hash then value.keys.sort.to_h { |key| [key, canonical(value[key])] }
        when Array then value.map { |item| canonical(item) }
        else value
        end
      end
      def digest(value) = Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
      def metadata(page)
        row = PageMetadata.find_by(site_id: page.site_id, page_id: page.id)
        row ? {'exists' => true, 'title_tag' => row.title_tag, 'description' => row.description, 'id' => row.id, 'revision' => row.lock_version, 'updated_by_id' => row.updated_by_id} : {'exists' => false}
      end
      def snapshot(page)
        sections = page.sections.order(:id).limit(81).to_a
        raise Limit, 'Page has more than 80 sections.' if sections.size > 80
        data = {'page' => page.attributes.slice('id', 'site_id', 'title', 'slug', 'published'), 'metadata' => metadata(page),
          'sections' => sections.map { |row| row.attributes.slice('id', 'kind', 'position', 'data', 'updated_at') },
          'site_context' => digest(page.site.attributes.slice('active_template_id', 'manifest'))}
        raise Limit, 'Page source exceeds 256 KB.' if data.to_json.bytesize > 256_000
        data
      end
      def fingerprint(page) = digest(snapshot(page))
      def path(page) = page.slug == 'home' ? '/' : "/site/#{page.slug}"
      def fixable_section(page, node, field)
        kind = node.ancestors('[data-studio-section]').first&.[]('data-studio-section')
        records = page.sections.where(kind: kind).limit(2).to_a
        return {} unless records.one?
        record = records.first
        definition = LightekDesign::Catalog.section_definition(record.kind)
        blocks = field == 'image_alt' ? %w[hero split image] : %w[hero split cta footer]
        return {} unless definition && definition['designer'] && blocks.include?(definition['block']) && Array(definition['fields']).any? { |item| item['name'] == field }
        theme = LightekDesign::SiteTheme.current(page.site)
        if theme && theme['chrome_page_id'].to_i != page.id && Array(theme['chrome']).any? { |entry| entry['kind'] == kind && (entry['chrome_header'] || entry['chrome_footer']) }
          return {}
        end
        allowed = if field == 'image_alt'
          node.name == 'img' && node['src'] == LightekDesign::Catalog.safe_url(record.data['image_url'], image: true)
        elsif field == 'cta_url'
          node['class'].to_s.split.include?('ld-button') && node['href'] == LightekDesign::Catalog.safe_url(record.data['cta_url'])
        else
          node['class'].to_s.split.include?('ld-button') && node.text.strip == record.data['cta_label'].to_s.strip
        end
        allowed ? {'kind' => 'section', 'section_id' => record.id, 'field' => field} : {}
      end
    end
  end
end
