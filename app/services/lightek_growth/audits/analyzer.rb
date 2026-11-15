require 'nokogiri'
require 'uri'
module LightekGrowth
  module Audits
    class Analyzer
      VERSION = 'native-cms-v1'.freeze
      def self.call(page:, html:)
        new(page, html).call
      end
      def initialize(page, html)
        @page, @document, @findings = page, Nokogiri::HTML5.parse(html), []
      end
      def call
        title = @document.at_css('head title')&.text.to_s.strip
        if title.present?
          others = @page.site.pages.where(published: true).where.not(id: @page.id).order(:id).limit(501).pluck(:id, :title)
          overrides = PageMetadata.where(site_id: @page.site_id, page_id: others.map(&:first)).pluck(:page_id, :title_tag).to_h
          duplicate = others.first(500).find { |id, name| (overrides[id].presence || "#{name} · #{@page.site.name}").strip.casecmp?(title) }
          add('title_duplicate', 'low', 'Distinguish this page’s title', {'rendered_title' => title.first(300), 'other_page_id' => duplicate[0]}, metadata('title_tag')) if duplicate
          add('scan_limit', 'low', 'Title comparison reached its scope limit', {'comparison_pages' => 500}) if others.size > 500
        end
        description = @document.at_css('head meta[name="description"]')&.[]('content').to_s.strip
        add('title_missing', 'medium', 'Add a descriptive page title', {'rendered_title' => title}, metadata('title_tag')) if title.blank?
        add('title_length', 'low', 'Review a long page title', {'rendered_title' => title.first(300), 'characters' => title.length}, metadata('title_tag')) if title.length > 70
        add('description_missing', 'medium', 'Write this page’s search description', {'description' => description}, metadata('description')) if description.blank?
        add('description_length', 'low', 'Review a long search description', {'characters' => description.length}, metadata('description')) if description.length > 170
        body = @document.at_css('main#main-content') || @document.at_css('body')
        headings = body.css('h1').size
        add('heading_missing', 'medium', 'Give this page a main heading', {'h1_count' => headings}) if headings == 0
        add('heading_multiple', 'low', 'Review the page’s main heading structure', {'h1_count' => headings}) if headings > 1
        body.css('img').first(100).each do |node|
          target = Source.fixable_section(@page, node, 'image_alt')
          evidence = {'image_source' => node['src'].to_s.first(300), 'alt' => node['alt']}
          if !node.key?('alt')
            add('image_alt_missing', 'medium', 'Review an image without an alt attribute', evidence, target, node_locator(node, target))
          elsif node['alt'].blank? && target.present?
            add('image_description_review', 'low', 'Decide whether this image needs a description', evidence.merge('note' => 'An empty alt can be intentional for decorative images.'), target, node_locator(node, target))
          end
        end
        links = body.css('a[href]').first(300)
        targets = links.filter_map { |node| cms_slug(node['href']) }.uniq
        published = @page.site.pages.where(published: true, slug: targets).pluck(:slug)
        links.each do |node|
          href = node['href'].to_s
          target = Source.fixable_section(@page, node, 'cta_url')
          evidence = {'href' => href.first(500), 'label' => node.text.strip.first(160)}
          slug = cms_slug(href)
          if slug && !published.include?(slug)
            add('internal_link_missing', 'high', 'Repair a link to an unpublished or missing CMS page', evidence.merge('target_slug' => slug), target, node_locator(node, target))
          elsif href.strip.in?(['', '#'])
            add('placeholder_link', 'medium', 'Give this link a real destination', evidence, target, node_locator(node, target))
          elsif href.start_with?('#') && !node.ancestors('template').any? && !@document.css('[id]').any? { |item| item['id'] == href.delete_prefix('#') && !item.ancestors('template').any? }
            add('anchor_missing', 'medium', 'Review a link to a missing document anchor', evidence, {}, node_locator(node, {}))
          end
          if node.text.strip.downcase.in?(['learn more', 'click here', 'here', 'submit'])
            label_target = Source.fixable_section(@page, node, 'cta_label')
            add('cta_label_review', 'low', 'Make the next action more specific', evidence.merge('note' => 'This label may be appropriate in context; review rather than automatically replace it.'), label_target, node_locator(node, label_target))
          end
        end
        if body.css('a[href]').size > 300 || body.css('img').size > 100
          add('scan_limit', 'low', 'Review content beyond this page’s scan limit', {'links' => body.css('a[href]').size, 'images' => body.css('img').size})
        end
        @findings
      end
      private
      def metadata(field) = {'kind' => 'metadata', 'field' => field}
      def add(rule, severity, title, evidence, target = {}, locator = 'page')
        @findings << {rule: rule, locator: locator, severity: severity, title: title, evidence: evidence, fix_target: target}
      end
      def node_locator(node, target)
        target.present? ? "section-#{target.fetch('section_id')}-#{target.fetch('field')}" : Source.digest([node.path, node['href'], node['src']]).first(24)
      end
      def cms_slug(href)
        uri = URI.join("https://#{@page.site.host}#{Source.path(@page)}", href.to_s)
        return unless uri.scheme.in?(%w[http https]) && uri.host.to_s.casecmp?(@page.site.host) && uri.port.in?([80, 443])
        match = URI::DEFAULT_PARSER.unescape(uri.path).match(%r{\A/site/([^/]+)/?\z})
        match && match[1]
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
