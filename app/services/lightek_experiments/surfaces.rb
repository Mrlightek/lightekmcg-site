# frozen_string_literal: true

module LightekExperiments
  module Surfaces
    WEBSITE_EVENTS = %w[inquiry demo_request checkout reservation].freeze
    RULES = {
      'website_headline' => ['Website hero headline', WEBSITE_EVENTS],
      'website_cta' => ['Website hero button', WEBSITE_EVENTS],
      'sales_inquiry' => ['Sales inquiry form button', %w[inquiry]],
      'demo_walkthrough' => ['Demo walkthrough button', %w[demo_request]],
      'demo_request' => ['Demo request form button', %w[demo_request]],
      'commerce_checkout' => ['Store checkout button', %w[checkout]],
      'reservation' => ['Local reservation button', %w[reservation]],
      'pwa_signup' => ['PWA member signup button', %w[member_signup]]
    }.freeze
    SITEWIDE = %w[sales_inquiry demo_request commerce_checkout reservation pwa_signup].freeze
    module_function

    def target!(site, surface, target)
      raise ArgumentError, 'Choose a supported experiment surface.' unless RULES.key?(surface)
      return '' if SITEWIDE.include?(surface)

      if surface == 'demo_walkthrough'
        showcase = LightekGrowth::FeatureShowcase.where(site: site).find_by(id: target)
        unless showcase&.approved_at && showcase.page.published? && showcase.snapshot['demo_promotion_link_id'] && !showcase.demo_experiment_started_at
          raise ArgumentError, 'Choose an approved, published walkthrough without a legacy button experiment.'
        end

        return showcase.id.to_s
      end
      raise ArgumentError, 'Select a published native hero section.' unless target.to_s.match?(/\A[1-9][0-9]{0,17}\z/)
      page_ids = site.pages.where(published: true).select(:id)
      section = DymondSite::Section.where(page_id: page_ids).find_by(id: target)
      definition = LightekDesign::Catalog.section_definition(section.kind) if section
      key = surface == 'website_headline' ? 'heading' : 'cta_label'
      unless definition&.fetch('block', nil) == 'hero' && section.data[key].present?
        raise ArgumentError, 'Select a published native hero section with the text to test.'
      end

      section.id.to_s
    end
  end
end
