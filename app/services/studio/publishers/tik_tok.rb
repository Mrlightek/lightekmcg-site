# frozen_string_literal: true
module Studio
  module Publishers
    class TikTok < SocialTransport
      API='https://open.tiktokapis.com/v2/post/publish'.freeze
      def self.options!(connection:,actor:,project:)
        connection!(connection.id,actor:actor,project:project)
        raise ArgumentError,'Choose a TikTok account' unless connection.provider=='tiktok'
        LightekMarketing::TiktokTokenRefreshJob.perform_now(connection.id) if LightekMarketing::SocialVault.checkout!(connection:connection)['refresh_token'].present?
        credentials=LightekMarketing::SocialVault.checkout!(connection:connection)
        raise ArgumentError,'Reconnect TikTok with the approved video.publish scope to use Direct Post' unless credentials.fetch('scope','').split(/[,\s]+/).include?('video.publish')
        http!(URI("#{API}/creator_info/query/"),credentials.fetch('access_token')).fetch('data').slice('creator_nickname','creator_username','privacy_level_options','comment_disabled','duet_disabled','stitch_disabled','max_video_post_duration_sec')
      end
      def call
        return refresh! if state['remote_id']
        confirm_review!
        actor=User.find(publication.metadata.fetch('user_id'))
        options=self.class.options!(connection:connection,actor:actor,project:publication.studio_project)
        @credentials=nil
        settings=publication.metadata.fetch('tiktok_settings',{})
        required=%w[privacy_level disable_comment disable_duet disable_stitch brand_content_toggle brand_organic_toggle is_aigc]
        raise ArgumentError,'Choose TikTok privacy, interaction, commercial-content and AI-content settings explicitly' unless settings.is_a?(Hash) && (settings.keys-required).empty? && required.all? { |key| settings.key?(key) } && (required-['privacy_level']).all? { |key| [true,false].include?(settings[key]) }
        raise ArgumentError,'Choose an available TikTok privacy level from the current creator options' unless Array(options['privacy_level_options']).include?(settings['privacy_level'])
        %w[comment duet stitch].each { |kind| raise ArgumentError,"This creator has disabled #{kind}" if options["#{kind}_disabled"] && !settings["disable_#{kind}"] }
        raise ArgumentError,'Branded content cannot use private visibility' if settings['brand_content_toggle'] && settings['privacy_level']=='SELF_ONLY'
        raise ArgumentError,'TikTok captions must be at most 2200 UTF-16 code units' if caption.encode('UTF-16LE').bytesize/2>2200
        seconds=duration
        raise ArgumentError,'Create a shorter cut for this TikTok account' unless seconds.finite? && seconds>0 && seconds<=Float(options.fetch('max_video_post_duration_sec'))
        url=video_url
        raise ArgumentError,'Verify this public video host in TikTok and LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS' unless LightekMarketing::TiktokVideoUpload.verified_host?(URI(url).host)
        save_state!('phase'=>'requesting','creator_username'=>options['creator_username'])
        result=self.class.http!(URI("#{API}/video/init/"),credentials.fetch('access_token'),{'post_info'=>settings.merge('title'=>caption),'source_info'=>{'source'=>'PULL_FROM_URL','video_url'=>url}})
        remote=result.dig('data','publish_id').presence || raise('TikTok returned no publish reference')
        save_state!('phase'=>'processing','remote_id'=>remote.to_s)
        {'status'=>'processing','remote_id'=>remote.to_s}
      rescue StandardError=>error
        uncertain!(error)
      end
      def refresh!
        confirm_review!
        LightekMarketing::TiktokTokenRefreshJob.perform_now(connection.id) if LightekMarketing::SocialVault.checkout!(connection:connection)['refresh_token'].present?
        @credentials=nil
        result=self.class.http!(URI("#{API}/status/fetch/"),credentials.fetch('access_token'),{'publish_id'=>state.fetch('remote_id')}).fetch('data')
        case result.fetch('status')
        when 'PUBLISH_COMPLETE'
          save_state!('phase'=>'published','provider_status'=>'PUBLISH_COMPLETE','public_post_ids'=>Array(result['publicaly_available_post_id']))
          {'status'=>'published','remote_id'=>state['remote_id']}
        when 'FAILED'
          save_state!('phase'=>'failed','provider_status'=>'FAILED','failure_code'=>result['fail_reason'].to_s.first(200))
          raise ArgumentError,"TikTok rejected publication: #{result['fail_reason'].to_s.gsub(/[^a-zA-Z0-9_-]/,'').first(100)}"
        when 'PROCESSING_UPLOAD','PROCESSING_DOWNLOAD'
          save_state!('provider_status'=>result['status'])
          {'status'=>'processing','remote_id'=>state['remote_id']}
        else
          raise NeedsReview,'TikTok returned an unexpected Direct Post state; reconcile its reference'
        end
      end
    end
  end
end
