# frozen_string_literal: true
require 'digest'
module LightekMarketing
  # Native, reproducible creative assembly. Facts and media remain actor/site scoped;
  # the private review render is never an approval or a social publication.
  class CampaignProducer
    CAPABILITY = 'marketing.campaign.produce'
    FIELDS = %w[service tone description audience cta_label cta_url image_ids].freeze
    def self.authorize!(actor, site)
      LightekGrowth::Workspace.new(actor: actor, site: site).revalidate!
      Studio::Broadcasting::Access.authorize!(actor, site)
    rescue LightekAgency::PackagePolicy::Denied => error
      raise ArgumentError, error.message
    end
    def self.inputs(raw)
      raise ArgumentError, 'Campaign inputs must be an object' unless raw.is_a?(Hash)
      data = raw.deep_stringify_keys
      raise ArgumentError, 'Unknown campaign input' unless (data.keys - FIELDS).empty?
      limits = {'service'=>80, 'description'=>140, 'audience'=>140, 'cta_label'=>60, 'cta_url'=>1200}
      limits.each do |key, limit|
        next unless data.key?(key)
        raise ArgumentError, "#{key} must be text of at most #{limit} characters" unless data[key].is_a?(String) && data[key].strip.length.between?(1, limit) && !data[key].match?(/[\x00-\x1f\x7f]/)
        data[key] = data[key].strip
      end
      raise ArgumentError, 'Name the service to promote' if data['service'].blank?
      data['tone'] ||= 'funny'
      raise ArgumentError, 'Choose funny or professional' unless %w[funny professional].include?(data['tone'])
      if data['cta_url']
        url = URI.parse(data['cta_url'])
        raise ArgumentError, 'Use an HTTPS destination without credentials' unless url.is_a?(URI::HTTPS) && url.host.present? && !url.userinfo
      end
      data['image_ids'] ||= []
      raise ArgumentError, 'Choose up to four image IDs' unless data['image_ids'].is_a?(Array) && data['image_ids'].size <= 4 && data['image_ids'].all? { |id| id.is_a?(Integer) && id.positive? }
      data
    rescue URI::InvalidURIError
      raise ArgumentError, 'Use an HTTPS destination'
    end
    def self.start!(actor:, site:, values:, request_key:)
      authorize!(actor, site)
      values = inputs(values)
      key = request_key.to_s
      raise ArgumentError, 'Use a request key of 16–100 letters, digits, underscores or hyphens' unless key.match?(/\A[a-zA-Z0-9_-]{16,100}\z/)
      fingerprint = Digest::SHA256.hexdigest(JSON.generate([site.id, values.sort.to_h]))
      operation = nil
      actor.with_lock do
        operation = StudioOperation.joins(:studio_project).where(studio_projects: {owner_id: actor.id}, capability: CAPABILITY).where("studio_operations.metadata ->> 'request_key' = ?", key).first
        if operation
          raise ArgumentError, 'This request key belongs to a different campaign' unless operation.metadata['input_fingerprint'] == fingerprint
          next
        end
        access = Studio::PwaAccess.new('user_id'=>actor.id, 'site_id'=>site.id)
        images = StudioAsset.for_actor(access).where(site_id: site.id, id: values['image_ids'], kind: 'image', status: 'ready').to_a
        raise ArgumentError, 'Choose ready images from this business' unless images.size == values['image_ids'].uniq.size && images.all? { |asset| asset.file.attached? }
        raise ArgumentError, 'Keep source images within 100 MB per campaign' if images.sum { |asset| asset.file.blob.byte_size } > 100.megabytes
        brief = LightekGrowth::Brief.find_by(site_id: site.id)
        # An unrelated business brief must never become a claim about this service.
        matching = brief && brief.offering.to_s.strip.casecmp?(values['service'])
        description = values['description'] || (brief.value_proposition if matching && brief.value_proposition.to_s.length.between?(1,140))
        audience = values['audience'] || (brief.audience if matching)
        cta = values.fetch('cta_label', 'Learn more')
        campaign = Campaign.create!(site: site, name: "#{values['service']} · #{values['tone']} TikTok ad", channel: 'social', status: 'draft', production_format: 'portrait', headline: "Meet #{values['service']}", message: description || "Discover #{values['service']}.", cta_label: cta, cta_url: values['cta_url'], content_review_required: true)
        scene = StudioProduction.open!(campaign: campaign, actor: actor)
        cards = values['tone'] == 'funny' ? ['My to-do list just hired a to-do list.', 'The meeting about the meeting can wait.'] : ['Time for a fresh introduction.', 'Meet your next possibility.']
        cards += [description || "Meet #{values['service']}.", "#{values['service']}\n#{cta}"]
        plan = {'version'=>1, 'platform'=>'tiktok', 'format'=>'portrait', 'duration'=>24, 'tone'=>values['tone'], 'service'=>values['service'], 'audience'=>audience, 'description'=>description, 'destination'=>values['cta_url'], 'image_ids'=>values['image_ids'], 'cards'=>cards,
          'source'=>{'brief_id'=>matching ? brief.id : nil, 'brief_revision'=>matching ? brief.lock_version : nil, 'provided_fields'=>values.keys, 'claims'=>description ? [description] : []},
          'review_notes'=>description ? ['Confirm business claims and destination before publication.'] : ['Generic introduction: add service benefits, audience and destination before publication.'],
          'tools'=>%w[script storyboard graphics timeline captions motion music private_preview], 'planner'=>'native_campaign_recipe_v1'}
        scene.update!(settings: scene.settings.merge('campaign_production_brief'=>{'offer'=>values['service'], 'audience'=>audience, 'business_goal'=>matching ? brief.goal : nil, 'call_to_action'=>cta, 'destination'=>values['cta_url'], 'format'=>'portrait', 'content_digest'=>campaign.content_digest}))
        operation = scene.studio_operations.create!(studio_project: scene.studio_project, operation_type: 'edit_media', provider: 'ffmpeg', capability: CAPABILITY, status: 'pending', intent: {'user_id'=>actor.id}, manifest: {'campaign_plan'=>plan}, metadata: {'request_key'=>key, 'input_fingerprint'=>fingerprint, 'campaign_id'=>campaign.id, 'draft_preview'=>true, 'initial_scene_version'=>scene.reload.lock_version})
      end
      CampaignProductionJob.perform_later(operation.id) if operation.status == 'pending'
      receipt(operation, actor: actor)
    end
    def self.find!(id, actor:)
      operation = StudioOperation.joins(:studio_project).where(studio_projects: {owner_id: actor.id}, capability: CAPABILITY).find(id)
      authorize!(actor, operation.studio_project.site)
      operation
    end
    def self.retry!(id, actor:)
      operation = find!(id, actor: actor)
      operation.with_lock do
        raise ArgumentError, 'Only failed campaign productions can be retried' unless operation.status == 'failed'
        operation.update!(status: 'pending', error_message: nil, completed_at: nil)
      end
      CampaignProductionJob.perform_later(operation.id)
      receipt(operation, actor: actor)
    end
    def self.receipt(operation, actor:)
      find!(operation.id, actor: actor)
      site_id = operation.studio_project.site_id
      scene_id = operation.studio_scene_id
      artifact = operation.artifacts.where(kind: 'video').order(:id).last if operation.status == 'completed'
      links = [{'label'=>'Open editable Studio production', 'url'=>"/dashboard/studio-broadcasting/workspace/#{scene_id}?site_id=#{site_id}&workspace=timeline"}, {'label'=>'Review campaign copy', 'url'=>"/dashboard/marketing/campaigns/#{operation.metadata.fetch('campaign_id')}/edit?site_id=#{site_id}"}]
      links << {'label'=>'Watch private draft preview', 'url'=>Rails.application.routes.url_helpers.rails_blob_path(artifact.file, only_path: true)} if artifact&.file&.attached?
      {'operation_id'=>operation.id, 'site_id'=>site_id, 'production_id'=>operation.production_id, 'scene_id'=>scene_id, 'campaign_id'=>operation.metadata['campaign_id'], 'status'=>operation.status, 'error'=>operation.error_message, 'plan'=>operation.manifest.fetch('campaign_plan'), 'links'=>links,
        'text'=>"Campaign production ##{operation.id}: #{operation.status}. #{operation.status == 'completed' ? 'The worker assembled' : 'The worker prepares'} script, storyboard, graphics, music and captions in Studio. This is a private draft. Use /campaign status #{operation.id} for the preview or /campaign retry #{operation.id} after a failure. Review and publishing remain separate."}
    end
  end
end
