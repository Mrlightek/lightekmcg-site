# frozen_string_literal: true

require 'digest'

module LightekGrowth
  class DemoCampaign
    LABELS = { 'control' => 'Request a demo', 'challenger' => 'Try Lightek with a demo' }.freeze

    def initialize(actor:, site:)
      @actor, @site = actor, site
    end

    def publish!(showcase_id:)
      @site.with_lock do
        ShowcaseBuilder.new(actor: @actor, site: @site).authorize!
        showcase, link = records!(showcase_id)
        verify_walkthrough!(showcase, link)
        showcase.page.update!(published: true)
        { 'page_id' => showcase.page_id, 'published' => true, 'walkthrough_path' => link.destination_path }
      end
    end

    def schedule!(showcase_id:, connection_id:, scheduled_at:, request_key:, time_zone: 'UTC')
      @site.with_lock do
        calendar = LightekMarketing::PublicationCalendar.new(actor: @actor, site: @site)
        calendar.authorize!
        showcase, link = records!(showcase_id)
        verify_walkthrough!(showcase, link)
        raise ArgumentError, 'Publish the walkthrough before scheduling.' unless showcase.page.published?

        campaign = showcase.marketing_kit.campaign
        expected_url = "#{SearchDiscovery.origin(@site)}/g/#{link.token}"
        raise ArgumentError, 'Approve promotion copy with this walkthrough’s tracked link before scheduling.' unless campaign.cta_url == expected_url

        slot = calendar.schedule!(
          campaign_id: campaign.id, connection_id: connection_id, scheduled_at: scheduled_at, request_key: request_key, time_zone: time_zone)
        { 'page_id' => showcase.page_id, 'slot_id' => slot.id, 'publication_status' => slot.status }
      end
    end

    def launch!(showcase_id:, connection_id:, scheduled_at:, request_key:, time_zone: 'UTC')
      @site.with_lock do
        publish!(showcase_id: showcase_id).merge(
          schedule!(showcase_id: showcase_id, connection_id: connection_id, scheduled_at: scheduled_at,
            request_key: request_key, time_zone: time_zone))
      end
    end

    def experiment!(showcase_id:)
      @site.with_lock do
        ShowcaseBuilder.new(actor: @actor, site: @site).authorize!
        showcase, link = records!(showcase_id)
        verify_walkthrough!(showcase, link)
        raise ArgumentError, 'Publish the walkthrough before starting its experiment.' unless showcase.page.published?

        showcase.update!(demo_experiment_started_at: Time.current) unless showcase.demo_experiment_started_at
        report!(showcase_id: showcase.id)
      end
    end

    def report!(showcase_id:)
      Workspace.new(actor: @actor, site: @site).revalidate!
      showcase, link = records!(showcase_id)
      funnel = DemoShowcase.funnel(@site, link.campaign_id)
      arms = LABELS.map do |variant, label|
        visits = DemoExposure.where(showcase: showcase, variant: variant).select(:visit_id)
        counts = DemoShowcase.outcomes(@site, Visit.where(site: @site, link: link, id: visits))
        conversions = LightekAgency::DemoRequest.where(agency_id: @site.tenant_id, growth_visit_id: visits).distinct.count(:growth_visit_id)
        counts.merge(variant: variant, label: label,
          request_rate: counts[:visits].positive? ? (100.0 * conversions / counts[:visits]).round(2) : nil)
      end
      summary = "#{funnel[:visits]} tracked visits, #{funnel[:requests]} demo requests, #{funnel[:activated]} activated demos, and #{funnel[:paid]} paid upgrades."
      if showcase.demo_experiment_started_at
        comparison = arms.map do |arm|
          rate = arm[:request_rate] ? "#{arm[:request_rate]}% requested a demo" : 'waiting for visits'
          "#{arm[:label]}: #{arm[:visits]} assigned visits, #{rate}"
        end
        summary = ([summary] + comparison).join("\n")
      end
      { 'text' => summary, 'showcase_id' => showcase.id, 'published' => showcase.page.published?, 'funnel' => funnel.stringify_keys,
        'experiment_started_at' => showcase.demo_experiment_started_at&.iso8601,
        'arms' => arms.map(&:stringify_keys) }
    end

    def self.ensure_promotion_available!(campaign)
      token = campaign.cta_url.to_s[%r{/g/([0-9a-f]{32})\z}, 1]
      return unless token

      link = Link.find_by(campaign_id: campaign.id, site_id: campaign.site_id, label: 'Demo walkthrough', token: token)
      return unless link

      showcase = FeatureShowcase.where(site_id: campaign.site_id)
        .find_by("CAST(snapshot ->> 'demo_promotion_link_id' AS TEXT) = ?", link.id.to_s)
      unless showcase && DemoShowcase.promotion_ready?(showcase, link)
        raise ArgumentError, 'The approved demo walkthrough or its request form is unavailable.'
      end
    end

    def self.record_exposure!(link, visit)
      showcase = FeatureShowcase.where(site_id: link.site_id).where.not(demo_experiment_started_at: nil)
        .find_by("CAST(snapshot ->> 'demo_promotion_link_id' AS TEXT) = ?", link.id.to_s)
      return unless showcase && visit.created_at >= showcase.demo_experiment_started_at && DemoShowcase.promotion_ready?(showcase, link)

      DemoExposure.create_or_find_by!(showcase: showcase, visit: visit) do |exposure|
        exposure.variant = Digest::SHA256.hexdigest("#{showcase.id}:#{visit.token}").last.to_i(16).even? ? 'control' : 'challenger'
      end
    end

    def self.cta(showcase, visit)
      return LABELS.fetch('control') unless visit && showcase.demo_experiment_started_at

      exposure = DemoExposure.find_by(showcase: showcase, visit: visit)
      LABELS.fetch(exposure&.variant || 'control')
    end

    private

    def records!(showcase_id)
      showcase = FeatureShowcase.where(site: @site).find(showcase_id)
      link = Link.where(site: @site, campaign: showcase.marketing_kit.campaign).find(showcase.snapshot['demo_promotion_link_id'])
      [showcase, link]
    end

    def verify_walkthrough!(showcase, link)
      unless SearchDiscovery.origin(@site) && DemoShowcase.demo_booking?(@site) && link.enabled? &&
             link.destination_path == "/site/#{showcase.page.slug}"
        raise ArgumentError, 'Restore the tracked walkthrough URL and enable the site’s demo request form.'
      end
      unless showcase.approved_at && showcase.status == 'completed' &&
             DemoShowcase.walkthrough_section?(showcase)
        raise ArgumentError, 'Approve the walkthrough media and keep its feature section on the page.'
      end
      DemoShowcase.verify_screenshots!(showcase)
    end
  end
end
