module LightekMarketing
  class PublicationCalendar
    def initialize(actor:, site:)
      @actor, @site = actor, site
    end
    def authorize!
      LightekGrowth::Workspace.new(actor: @actor, site: @site).revalidate!
      raise ArgumentError, 'An authorized publishing operator is required.' unless @actor.role.in?(%w[admin super_admin])
    end
    def self.parse_local(value:, zone:)
      timezone = Time.find_zone!(zone)
      raise ArgumentError, 'Choose a local date and time.' unless value.to_s.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/)
      local = DateTime.strptime(value, '%Y-%m-%dT%H:%M')
      raise ArgumentError, 'This local time is missing or ambiguous due to a clock change. Choose another time.' unless timezone.tzinfo.periods_for_local(local).size == 1
      timezone.local(local.year, local.month, local.day, local.hour, local.minute).iso8601
    end
    def schedule!(campaign_id:, connection_id:, scheduled_at:, request_key:, time_zone: 'UTC')
      @site.with_lock do
        authorize!
        raise ArgumentError, 'Scheduling request key required.' unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        Time.find_zone!(time_zone)
        raise ArgumentError, 'Use an ISO timestamp with timezone.' unless scheduled_at.to_s.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
        time = Time.iso8601(scheduled_at.to_s)
        old = PublicationSlot.find_by(site: @site, request_key: request_key)
        if old
          raise ArgumentError, 'Request key belongs to different inputs.' unless old.campaign_id.to_s == campaign_id.to_s && old.connection_id.to_s == connection_id.to_s && old.scheduled_at.to_i == time.to_i && old.time_zone == time_zone
          return old
        end
        raise ArgumentError, 'Choose a future time within 90 days.' unless time > Time.current && time <= 90.days.from_now
        campaign = Campaign.where(site: @site).find(campaign_id)
        connection = SocialConnection.where(site: @site).find(connection_id)
        valid_inputs!(campaign, connection)
        raise ArgumentError, 'This campaign already has a provider request for this account.' if SocialPost.where(campaign: campaign, connection: connection).exists?
        if PublicationSlot.where(campaign: campaign, connection: connection).where.not(status: 'canceled').exists?
          raise ArgumentError, 'Cancel the existing slot before scheduling another.'
        end
        slot = PublicationSlot.create!(site: @site, campaign: campaign, connection: connection, scheduled_by: @actor, scheduled_at: time, time_zone: time_zone, request_key: request_key, content_digest: campaign.content_digest)
        log('social_scheduled', slot)
        slot
      end
    rescue ArgumentError => error
      raise ArgumentError, error.message == 'invalid xmlschema format' ? 'Use an ISO timestamp with timezone.' : error.message
    end
    def cancel!(id:, version:)
      @site.with_lock do
        authorize!
        slot = PublicationSlot.where(site: @site).find(id)
        return slot if slot.status == 'canceled'
        raise ActiveRecord::StaleObjectError.new(slot, 'update') unless version.to_s.match?(/\A\d+\z/) && slot.lock_version == version.to_i
        raise ArgumentError, 'Submission has started. Reconcile it with the provider instead of canceling locally.' unless slot.status.in?(%w[scheduled blocked]) && !slot.started_at
        slot.update!(status: 'canceled', finished_at: Time.current)
        log('social_canceled', slot)
        slot
      end
    end
    def dispatch!(id)
      slot = PublicationSlot.where(site: @site).find(id)
      # Commit the claim before provider IO. A lost/unknown response is never retried automatically.
      @site.with_lock do
        slot.reload
        return slot unless slot.status == 'scheduled' && slot.scheduled_at <= Time.current
        begin
          authorize!
          raise ArgumentError, 'Scheduled operator changed.' unless slot.scheduled_by_id == @actor.id
          valid_inputs!(slot.campaign.reload, slot.connection.reload)
          raise ArgumentError, 'Reviewed campaign content changed. Cancel and schedule the new version.' unless slot.campaign.content_digest == slot.content_digest
          raise ArgumentError, 'Another provider request already exists.' if SocialPost.where(campaign: slot.campaign, connection: slot.connection).exists?
        rescue ArgumentError, ActiveRecord::RecordNotFound, LightekAgency::PackagePolicy::Denied => error
          slot.update!(status: 'blocked', error_message: error.message.first(1000), finished_at: Time.current)
          log('social_blocked', slot)
          return slot
        end
        post = SocialPost.create!(campaign: slot.campaign, connection: slot.connection)
        slot.update!(status: 'dispatching', started_at: Time.current, social_post: post)
      end
      SocialDispatch.call!(post: slot.social_post, expected_digest: slot.content_digest, actor: @actor)
      slot.reload
      post = slot.social_post.reload
      slot.update!(status: post.status == 'published' ? 'published' : post.remote_id.present? ? 'submitted' : 'needs_review', finished_at: Time.current)
      log('social_result', slot)
      slot
    rescue StandardError => error
      if slot&.persisted? && slot.reload.status == 'dispatching'
        post = slot.social_post
        post&.with_lock do
          post.update!(status: 'needs_review', error: 'Calendar submission outcome requires provider reconciliation.') if post.status == 'pending' && post.remote_id.blank?
        end
        slot.update!(status: 'needs_review', error_message: "Provider outcome requires reconciliation: #{error.class.name}".first(1000), finished_at: Time.current)
        log('social_needs_review', slot)
      end
      raise
    end
    private
    def valid_inputs!(campaign, connection)
      raise ArgumentError, 'Approve the current social campaign version in Content review before scheduling.' unless campaign.channel == 'social' && campaign.status == 'ready' && campaign.content_review_required? && campaign.content_approved?
      raise ArgumentError, 'Destination is disconnected.' unless connection.enabled?
      raise ArgumentError, 'Choose a configured Facebook, Instagram or TikTok adapter.' unless connection.provider.in?(%w[facebook instagram tiktok])
      raise ArgumentError, 'Campaign media is unavailable or changed.' unless campaign.media_ready?
      if connection.provider == 'facebook' && campaign.media_url.present?
        raise ArgumentError, 'The current Facebook adapter publishes text/link posts. Choose an image/video-capable destination for media.'
      elsif connection.provider == 'instagram'
        raise ArgumentError, 'The current Instagram adapter requires a JPEG or PNG image.' unless campaign.media_url.to_s.match?(/\.(jpg|jpeg|png)(\?.*)?\z/i)
      elsif connection.provider == 'tiktok'
        uri = URI.parse(campaign.media_url.to_s)
        raise ArgumentError, 'TikTok requires a video URL under an operator-verified host.' unless campaign.media_url.to_s.match?(/\.mp4(?:\?.*)?\z/i) && TiktokVideoUpload.verified_host?(uri.host)
      end
    rescue URI::InvalidURIError
      raise ArgumentError, 'Campaign media URL is invalid.'
    end
    def log(event, slot)
      Rails.logger.info({event: "lightek.growth.#{event}", site_id: @site.id, actor_id: @actor.id, campaign_id: slot.campaign_id, publication_slot_id: slot.id, status: slot.status}.to_json)
    end
  end
end
