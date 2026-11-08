require 'uri'
module Studio
  module Live
    module Audience
      module_function
      PURPOSE = 'live_audience'
      CONSUMER = 'Studio::Live::Audience'
      def slug(user) = "studio-audience-#{user.id}"
      def validate_chat_url!(url)
        uri = URI.parse(url.to_s.strip)
        raise ArgumentError, 'Use the embed URL from Restream Chat settings.' unless uri.scheme == 'https' &&
          uri.host == 'chat.restream.io' && uri.path == '/embed' && uri.port == 443 && !uri.userinfo && !uri.fragment && uri.query.present? && uri.to_s.bytesize <= 4096
        uri.to_s
      rescue URI::InvalidURIError
        raise ArgumentError, 'Use the embed URL from Restream Chat settings.'
      end
      def settings(user)
        return {} unless LightekVault::Secret.where(slug: slug(user), status: 'active').exists?
        LightekVault::Service.checkout!(slug: slug(user), consumer: CONSUMER, purpose: PURPOSE, requested_by: "user:#{user.id}")
      rescue ActiveRecord::RecordNotFound, LightekVault::Service::AccessDenied
        {}
      end
      def save!(user:, chat_url: nil, tiktok_username: nil, ssn_session: nil, sign_api_key: nil)
        Gatekeeper::StudioLivePolicy.authorize!(user: user, configure: true)
        values = settings(user)
        values['chat_url'] = validate_chat_url!(chat_url) if chat_url.present?
        if tiktok_username.present?
          username = tiktok_username.to_s.strip.delete_prefix('@')
          raise ArgumentError, 'Enter a TikTok username, without a URL.' unless username.match?(/\A[A-Za-z0-9_.]{1,24}\z/)
          values['tiktok_username'] = username
        end
        if ssn_session.present?
          raise ArgumentError, 'Enter the Social Stream Ninja session ID.' unless ssn_session.to_s.match?(/\A[A-Za-z0-9_-]{8,128}\z/)
          values['ssn_session'] = ssn_session.to_s
        end
        if sign_api_key.present?
          raise ArgumentError, 'Invalid connector signing key.' unless sign_api_key.to_s.bytesize.between?(8, 2048) && !sign_api_key.to_s.match?(/[\s\x00-\x1f]/)
          values['sign_api_key'] = sign_api_key.to_s
        end
        raise ArgumentError, 'Enter a username, chat embed, or Social Stream Ninja session.' if values.empty?
        LightekVault::Service.store!(name: "Social audience · #{user.id}", slug: slug(user), provider: 'social', purpose: PURPOSE,
          payload: values, requested_by: user.email_address, access_policy: {'consumers'=>[CONSUMER], 'purposes'=>[PURPOSE]})
      end
      def chat_url(user)
        value = settings(user)['chat_url']
        validate_chat_url!(value) if value.present?
      rescue ArgumentError
        nil
      end
      def touch!(operation, user)
        return unless user && %w[live connecting].include?(operation.status)
        StudioLiveViewer.upsert({studio_live_operation_id: operation.id, user_id: user.id, last_seen_at: Time.current},
          unique_by: 'idx_lightek_live_viewer_identity')
      end
      def snapshot(operation, user)
        Studio::Live::Sessions.find!(operation.id, user)
        viewers = StudioLiveViewer.present_now.where(studio_live_operation: operation).includes(:user)
        comments = []
        if operation.metadata['post_id']
          access = LightekCommunity::Access.new(user: user, site_id: operation.studio_project.site_id)
          post = access.posts.find(operation.metadata.fetch('post_id'))
          comments = access.posts.where(parent_id: post.id).includes(:user).order(id: :desc).limit(50).to_a.reverse.map do |reply|
            {id: reply.id, name: reply.user.first_name, text: reply.content.to_s.first(2000)}
          end
        end
        {viewers: viewers.limit(100).map { |v| {name: v.user.first_name} }, viewer_count: viewers.count,
          comments: comments, observed_at: Time.current.iso8601, note: 'Signed-in Lightek viewers requesting playback in the last 45 seconds. Social viewers are not included.'}
      end
    end
  end
end
