require 'uri'
module LightekGrowth
  module Performance
    class Workspace
      COPY_FIELDS = %w[channel production_format headline message cta_label cta_url media_url media_binding_id].freeze
      def initialize(actor:, site:)
        @actor, @site = actor, site
        @access = LightekGrowth::Workspace.new(actor: actor, site: site)
      end
      def create!(values:, request_key:)
        request_key!(request_key)
        values = values.to_h.stringify_keys.slice(*%w[name hypothesis variable starts_on ends_on control_campaign_id challenger_campaign_id source medium control_path challenger_path confirmed])
        @site.with_lock do
          @access.revalidate!
          if (existing = Comparison.find_by(site: @site, request_key: request_key))
            raise ArgumentError, 'Request key belongs to another comparison.' unless existing.brief_snapshot['request_values'] == values
            return existing
          end
          brief = Brief.find_by(site: @site)
          raise ArgumentError, 'Complete the business brief first.' unless brief&.complete?
          raise ArgumentError, 'Confirm the pinned versions and intended placement.' unless values['confirmed'] == '1'
          ids = values.values_at('control_campaign_id', 'challenger_campaign_id')
          raise ArgumentError, 'Select two distinct reviewed social campaigns.' unless ids.all? { |id| id.to_s.match?(/\A[1-9][0-9]*\z/) } && ids.map(&:to_s).uniq.size == 2
          # Lock in ID order so concurrent content review cannot change either version.
          campaigns = LightekMarketing::Campaign.where(site: @site, id: ids).order(:id).lock.to_a
          raise ActiveRecord::RecordNotFound unless campaigns.size == 2
          campaigns.each do |campaign|
            unless campaign.channel == 'social' && campaign.content_review_required? && campaign.content_approved? && campaign.media_ready?
              raise ArgumentError, 'Both campaigns need current, explicit copy approval and usable bound media.'
            end
          end
          rows = ids.map { |id| campaigns.find { |row| row.id.to_s == id.to_s } }
          comparison = Comparison.create!(values.slice('name', 'hypothesis', 'variable', 'starts_on', 'ends_on').merge(site: @site, created_by: @actor, request_key: request_key,
            brief_snapshot: brief.attributes.slice(*Brief::FIELDS).merge('brief_id' => brief.id, 'revision' => brief.lock_version, 'request_values' => values)))
          %w[control challenger].zip(rows).each do |label, campaign|
            link = reviewed_link(campaign)
            in_copy = link.present?
            if link
              unless link.enabled? && link.source == values['source'] && link.medium == values['medium'] && link.destination_path == values["#{label}_path"]
                raise ArgumentError, 'The reviewed CTA uses a tracked link. Match its enabled source, medium and destination before pinning.'
              end
              raise ArgumentError, 'This reviewed link is already bound to a comparison. Create a new placement link and approve its copy first.' if ComparisonArm.exists?(link: link)
            else
              link = @access.create_link!(values: {'campaign_id' => campaign.id, 'label' => "#{comparison.name.first(120)} · #{label}", 'source' => values['source'], 'medium' => values['medium'], 'destination_path' => values["#{label}_path"]})
            end
            comparison.arms.create!(campaign: campaign, link: link, label: label, content_digest: campaign.content_digest,
              creative_snapshot: campaign.attributes.slice(*COPY_FIELDS).merge('campaign_name' => campaign.name, 'placement_link_in_copy' => in_copy, 'approved_by_id' => campaign.content_approved_by_id, 'approved_at' => campaign.content_approved_at.iso8601))
          end
          log('comparison_created', comparison_id: comparison.id)
          comparison
        end
      end
      def review!(comparison_id:, request_key:)
        request_key!(request_key)
        @site.with_lock do
          @access.revalidate!
          comparison = Comparison.where(site: @site).find(comparison_id)
          existing = comparison.reviews.find_by(request_key: request_key)
          return existing if existing
          now = Time.current
          review = comparison.reviews.create!(created_by: @actor, request_key: request_key, rules_version: Measurement::VERSION, measured_at: now,
            snapshot: Measurement.new(comparison: comparison, measured_at: now).call)
          log('performance_reviewed', comparison_id: comparison.id, review_id: review.id)
          review
        end
      end
      def followup!(review_id:)
        @site.with_lock do
          @access.revalidate!
          review = PerformanceReview.joins(:comparison).where(lightek_growth_comparisons: {site_id: @site.id}).find(review_id)
          if (prior = review.followup)
            raise ArgumentError, 'The prepared draft is unavailable; review the retained receipt.' unless LightekMarketing::Campaign.where(site: @site, id: prior.campaign_id).exists?
            return prior
          end
          raise ArgumentError, 'Prepare a fresh review before drafting.' unless review == review.comparison.reviews.order(id: :desc).first && review.measured_at >= 7.days.ago
          raise ArgumentError, 'Review rules changed; measure a fresh review.' unless review.rules_version == Measurement::VERSION
          raise ArgumentError, 'Collect and review evidence before preparing a follow-up.' unless review.snapshot.dig('recommendation', 'can_draft')
          label = review.snapshot.dig('recommendation', 'starting_arm')
          arm = review.comparison.arms.find_by!(label: label)
          source = arm.creative_snapshot.slice('headline', 'message', 'cta_label', 'production_format')
          # A new campaign must not inherit the old placement's attribution token.
          source['cta_url'] = URI::HTTPS.build(host: @site.host, path: arm.link.destination_path).to_s
          campaign = LightekMarketing::Campaign.create!(source.merge(site: @site, name: "Follow-up · #{review.comparison.name}".first(160), channel: 'social', status: 'draft', content_review_required: true))
          receipt = PerformanceDraft.create!(review: review, campaign: campaign, created_by: @actor)
          log('performance_draft_prepared', review_id: review.id, campaign_id: campaign.id)
          receipt
        end
      end
      def receipt(review)
        raise ActiveRecord::RecordNotFound unless review.comparison.site_id == @site.id
        @access.revalidate!
        {'status' => 'reviewed', 'site_id' => @site.id, 'comparison_id' => review.comparison_id, 'review_id' => review.id,
         'measured_at' => review.measured_at.iso8601, 'rules_version' => review.rules_version, 'recommendation' => review.snapshot.fetch('recommendation'),
         'url' => Rails.application.routes.url_helpers.dashboard_campaign_performance_path(site_id: @site.id, comparison_id: review.comparison_id, review_id: review.id)}
      end
      private
      def request_key!(key)
        raise ArgumentError, 'Use a request key of 8–100 letters, numbers, underscores or hyphens.' unless key.is_a?(String) && key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
      end
      def reviewed_link(campaign)
        url = URI.parse(campaign.cta_url.to_s)
        token = url.path.to_s.match(%r{\A/g/([0-9a-f]{32})\z})&.[](1)
        return unless url.scheme == 'https' && url.port == 443 && url.userinfo.nil? && url.host.to_s.casecmp?(@site.host) && token
        link = Link.where(site: @site, campaign: campaign).find_by(token: token)
        raise ArgumentError, 'The reviewed tracked CTA does not belong to this campaign.' unless link
        link
      rescue URI::InvalidURIError
        nil
      end
      def log(event, **fields)
        Rails.logger.info({event: "lightek.growth.#{event}", site_id: @site.id, actor_id: @actor.id}.merge(fields).to_json)
      end
    end
  end
end
