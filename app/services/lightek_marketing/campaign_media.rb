module LightekMarketing
  class CampaignMedia
    TYPES = {'image/jpeg' => 'jpg', 'image/png' => 'png', 'video/mp4' => 'mp4'}.freeze
    def initialize(actor:, site:)
      @actor, @site = actor, site
      @access = LightekGrowth::Workspace.new(actor: actor, site: site)
    end
    def artifacts
      @access.revalidate!
      projects = Studio::PwaAccess.new('user_id' => @actor.id, 'site_id' => @site.id).projects.where(site_id: @site.id)
      Artifact.joins(:studio_operation).where(kind: %w[image video], studio_operations: {studio_project_id: projects.select(:id), status: 'completed'}).order(id: :desc).limit(50)
    end
    def attach!(campaign_id:, artifact_id:, delivery_host: @site.host)
      @site.with_lock do
        @access.revalidate!
        campaign = Campaign.where(site: @site).find(campaign_id)
        campaign.with_lock do
          raise ArgumentError, 'Choose a social campaign for this media handoff.' unless campaign.channel == 'social'
          raise ArgumentError, 'Use a separate campaign after delivery or publication has started.' if SocialPost.where(campaign: campaign).exists? || Delivery.where(campaign: campaign).exists?
          artifact = artifacts.find(artifact_id)
          raise ArgumentError, 'Choose a completed full export, not a draft preview.' if artifact.studio_operation.metadata['draft_preview']
          raise ArgumentError, 'This export has no saved file.' unless artifact.file.attached?
          blob = artifact.file.blob
          extension = TYPES[blob.content_type]
          raise ArgumentError, 'Choose a JPEG, PNG or MP4 export up to 1 GB.' unless extension && blob.byte_size > 0 && blob.byte_size <= 1.gigabyte
          current = campaign.media_binding if campaign.media_binding_id
          return current if current && current.usable? && current.source_snapshot['blob_id'] == blob.id && campaign.media_url == current.public_url && current.delivery_host == delivery_host.to_s.downcase
          binding = MediaBinding.create!(site: @site, campaign: campaign, artifact: artifact, created_by: @actor, delivery_host: delivery_host.to_s.downcase, filename: "campaign-#{campaign.id}-export-#{artifact.id}.#{extension}",
            source_snapshot: {'artifact_id' => artifact.id, 'operation_id' => artifact.studio_operation_id, 'blob_id' => blob.id, 'checksum' => blob.checksum, 'content_type' => blob.content_type, 'byte_size' => blob.byte_size})
          binding.file.attach(blob)
          raise ArgumentError, 'The saved media file could not be attached.' unless binding.file.attached?
          campaign.update!(media_binding: binding, media_url: binding.public_url, content_review_required: true, status: 'draft')
          Rails.logger.info({event: 'lightek.growth.media_attached', site_id: @site.id, actor_id: @actor.id, campaign_id: campaign.id, media_binding_id: binding.id, artifact_id: artifact.id}.to_json)
          binding
        end
      end
    end
    def revoke!(id:)
      @site.with_lock do
        @access.revalidate!
        binding = MediaBinding.where(site: @site).find(id)
        return binding if binding.revoked_at
        binding.update!(revoked_at: Time.current)
        Rails.logger.info({event: 'lightek.growth.media_revoked', site_id: @site.id, actor_id: @actor.id, media_binding_id: binding.id}.to_json)
        binding
      end
    end
  end
end
