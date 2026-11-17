module LightekPwa
  class Publications
    def self.enqueue!(post)
      return unless post.site && LightekReservations::Federation::Client.config(post.site)
      return unless post.site.tenant_id == post.user_id && post.site.tenant_type == 'User'
      post.site.with_lock do
        row = PublicationOutbox.find_or_initialize_by(site_id: post.site_id, remote_post_id: post.id)
        source = Post.find_by(id: post.id)
        post = source if source
        visible = source.present? && !post.destroyed? && post.parent_id.nil? && post.community_id.nil? && post.visibility == 'public' && post.audience == 'everyone' && post.moderation_state == 'published' && (!post.expires_at || post.expires_at.future?)
        row.assign_attributes(revision: row.revision.to_i + 1, payload: {remote_post_id: post.id, removed: !visible,
          title: post.title.to_s.first(160), kind: post.kind, youtube_video_id: post.metadata['youtube_video_id'], expires_at: post.expires_at&.iso8601})
        row.save!
        LightekPwa::PublicationSyncJob.perform_later(row.id)
      end
    end
    def self.accept!(peer:, payload:)
      purchase = Purchase.find_by(order_id: peer.order_id) or raise Policy::Denied, 'This instance has no network membership'
      raise Policy::Denied, 'Instance membership is inactive' unless (purchase.entitled? || payload['removed'] == true) && LightekCommerce::Installations.ready?(peer.order) && peer.merchant_id == purchase.user_id
      id = Integer(payload.fetch('remote_post_id'))
      revision = Integer(payload.fetch('revision'))
      raise ArgumentError, 'Invalid publication identity' unless id.positive? && revision.positive? && id <= 9_000_000_000_000_000 && revision <= 9_000_000_000_000_000
      peer.with_lock do
        ref = PublicationReference.find_or_initialize_by(peer: peer, remote_post_id: id)
        return ref if ref.persisted? && revision <= ref.revision
        removed = payload['removed'] == true
        expires_at = payload['expires_at'].present? ? Time.iso8601(payload['expires_at']) : nil
        removed ||= expires_at && expires_at <= Time.current
        if removed
          # Retain the reference revision as a tombstone against late retries.
          post = ref.post
          ref.update!(post: nil, revision: revision, removed: true)
          post&.destroy!
        else
          kind = payload.fetch('kind')
          raise ArgumentError, 'Unsupported network post type' unless %w[post article photo video clip audio story event].include?(kind)
          origin = "https://#{LightekCommerce::Installations.hostname(peer.order)}"
          title = payload['title'].to_s.first(160).presence || "Post from #{purchase.user.profile.public_display_name}"
          post = ref.post || Post.new(user: purchase.user, site: purchase.site, visibility: 'public', audience: 'everyone')
          youtube_id = payload['youtube_video_id'].to_s
          metadata = {'remote_content' => {'peer_key' => peer.key, 'remote_post_id' => id,
            'fetch_url' => "#{origin}/api/lightek/network/posts/#{id}", 'post_url' => "#{origin}/lightek/index.html#/post/#{id}"}}
          metadata['youtube_video_id'] = youtube_id if youtube_id.match?(Youtube::ID)
          post.assign_attributes(title: title, kind: kind, content: nil, expires_at: expires_at,
            metadata: metadata)
          post.save!
          ref.update!(post: post, revision: revision, removed: false)
        end
        ref
      end
    end
  end
end
