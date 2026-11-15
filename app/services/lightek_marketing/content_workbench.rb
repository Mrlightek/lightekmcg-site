module LightekMarketing
  class ContentWorkbench
    ANGLES = {
      'offer' => ['{topic}', '{facts}', 'For {audience}.', '{call_to_action}'],
      'problem' => ['For {audience}: {obstacle}', '{topic}', '{facts}', '{call_to_action}'],
      'benefit' => ['{facts}', '{topic} — for {audience}.', '{call_to_action}']
    }.freeze
    def initialize(actor:, site:)
      @actor, @site = actor, site
      @access = LightekGrowth::Workspace.new(actor: actor, site: site)
    end
    def generate!(campaign_id:, request_key:, tracking_link_id: nil)
      raise ArgumentError, 'Generation request key required.' unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
      @site.with_lock do
        @access.revalidate!
        campaign = Campaign.where(site: @site).find(campaign_id)
        existing = ContentVariant.where(campaign: campaign, batch_key: request_key).order(:id)
        if existing.exists?
          expected = existing.first.source_snapshot['tracking_link_id'].to_s
          raise ArgumentError, 'Request key belongs to another tracking selection.' unless expected == tracking_link_id.to_s
          return existing.to_a
        end
        brief = LightekGrowth::Brief.find_by(site: @site)
        raise ArgumentError, 'Complete the business growth brief before preparing content.' unless brief&.complete?
        link = LightekGrowth::Link.where(site: @site, campaign: campaign, enabled: true).find(tracking_link_id) if tracking_link_id.present?
        cta = link ? Rails.application.routes.url_helpers.growth_link_url(token: link.token, host: @site.host, protocol: 'https') : (campaign.cta_url.to_s.start_with?('https://') ? campaign.cta_url : "https://#{@site.host}/")
        context = {'topic' => brief.offering, 'audience' => brief.audience, 'obstacle' => brief.customer_problem, 'facts' => brief.value_proposition, 'call_to_action' => campaign.cta_label.presence || 'Learn more'}
        snapshot = {'brief_id' => brief.id, 'brief_revision' => brief.lock_version, 'brief' => brief.attributes.slice(*LightekGrowth::Brief::FIELDS).transform_values { |v| v.is_a?(Date) ? v.iso8601 : v },
          'tracking_link_id' => link&.id, 'channel' => campaign.channel, 'provider' => 'rules', 'writer_version' => 'campaign-angles-v1'}
        ANGLES.map do |angle, templates|
          generated = NevaehIntelligences::WritingEngine.generate(format: 'post', actor: @actor, context: context,
            profile: {'format' => 'post', 'provider' => 'rules', 'templates' => templates, 'examples' => [], 'instructions' => brief.voice.to_s})
          ContentVariant.create!(site: @site, campaign: campaign, created_by: @actor, batch_key: request_key, angle: angle, status: 'draft',
            headline: brief.offering.first(200), message: generated.fetch('text'), cta_label: context.fetch('call_to_action').first(60), cta_url: cta, media_url: campaign.media_url,
            baseline_digest: campaign.content_digest, source_snapshot: snapshot.merge('editorial' => generated['editorial']))
        end.tap { |rows| log('content_generated', campaign_id: campaign.id, variant_ids: rows.map(&:id)) }
      end
    end
    def update!(id:, version:, values:)
      @site.with_lock do
        @access.revalidate!
        variant = ContentVariant.where(site: @site).find(id)
        version!(variant, version)
        raise ArgumentError, 'Approved copy is immutable. Generate another draft.' unless variant.status == 'draft'
        variant.update!(values.to_h.stringify_keys.slice(*ContentVariant::COPY_FIELDS))
        log('content_edited', campaign_id: variant.campaign_id, variant_id: variant.id, revision: variant.lock_version)
        variant
      end
    end
    def approve!(id:, version:)
      @site.with_lock do
        @access.revalidate!
        variant = ContentVariant.where(site: @site).find(id)
        campaign = Campaign.where(site: @site).find(variant.campaign_id)
        campaign.with_lock do
          if variant.status == 'approved'
            raise ArgumentError, 'This approval no longer matches the campaign. Generate a new content set.' unless campaign.content_approved? && campaign.content_digest == variant.applied_digest
            return variant
          end
          version!(variant, version)
          brief = LightekGrowth::Brief.find_by(site: @site)
          source = variant.source_snapshot
          raise ArgumentError, 'The brief changed. Generate a new content set.' unless brief && brief.id == source['brief_id'] && brief.lock_version == source['brief_revision']
          raise ArgumentError, 'The campaign copy changed. Generate a new content set.' unless campaign.content_digest == variant.baseline_digest
          if campaign.has_attribute?(:sent_at) && campaign.sent_at.present? || Delivery.where(campaign: campaign).exists? || SocialPost.where(campaign: campaign).exists?
            raise ArgumentError, 'This campaign has delivery/publication history. Create a separate campaign for new copy.'
          end
          link_id = source['tracking_link_id']
          if link_id && !LightekGrowth::Link.where(site: @site, campaign: campaign, id: link_id, enabled: true).exists?
            raise ArgumentError, 'The selected tracking link was disabled. Generate a new content set.'
          end
          campaign.assign_attributes(variant.attributes.slice(*ContentVariant::COPY_FIELDS))
          campaign.assign_attributes(content_review_required: true, approved_content_digest: campaign.content_digest, content_approved_by: @actor, content_approved_at: Time.current, status: 'ready')
          campaign.save!
          # Keep the source immutable; applied fingerprint has its own result column.
          variant.update!(status: 'approved', approved_by: @actor, approved_at: Time.current, applied_digest: campaign.content_digest)
          log('content_approved', campaign_id: campaign.id, variant_id: variant.id, digest: campaign.content_digest)
          variant
        end
      end
    end
    private
    def version!(variant, version)
      raise ActiveRecord::StaleObjectError.new(variant, 'update') unless version.to_s.match?(/\A\d+\z/) && variant.lock_version == version.to_i
    end
    def log(event, **fields)
      Rails.logger.info({event: "lightek.growth.#{event}", site_id: @site.id, actor_id: @actor.id}.merge(fields).to_json)
    end
  end
end
