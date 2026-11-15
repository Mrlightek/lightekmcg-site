# frozen_string_literal: true
module Studio
  module Publishers
    class Instagram < SocialTransport
      def graph(path,values={},method: :post)
        version=ENV.fetch('LIGHTEK_META_GRAPH_VERSION','v22.0')
        raise ArgumentError,'Choose a versioned Meta Graph API' unless version.match?(/\Av[0-9]+\.0\z/)
        self.class.http!(URI("https://graph.facebook.com/#{version}/#{path}"),credentials.fetch('access_token'),values,method:method)
      end
      def account
        value=credentials.fetch('instagram_user_id').to_s
        raise ArgumentError,'Reconnect a valid Instagram professional account' unless value.match?(/\A[0-9]+\z/)
        value
      end
      def call
        return refresh! if state['remote_id']
        confirm_review!
        raise ArgumentError,'Instagram captions must contain at most 2200 characters' if caption.length>2200
        id=account;url=video_url
        save_state!('phase'=>'requesting')
        result=graph("#{id}/media",{'media_type'=>'REELS','video_url'=>url,'caption'=>caption,'share_to_feed'=>true})
        container=result.fetch('id').to_s
        raise ArgumentError,'Instagram returned an invalid container' unless container.match?(/\A[0-9]+\z/)
        save_state!('phase'=>'processing','remote_id'=>container)
        {'status'=>'processing','remote_id'=>container}
      rescue StandardError=>error
        uncertain!(error)
      end
      def refresh!
        confirm_review!(allow_uncertain:true)
        container=state.fetch('remote_id')
        raise ArgumentError,'Invalid Instagram container reference' unless container.to_s.match?(/\A[0-9]+\z/)
        result=graph(container,{'fields'=>'status_code,status'},method: :get)
        case result.fetch('status_code')
        when 'IN_PROGRESS'
          {'status'=>'processing','remote_id'=>container}
        when 'FINISHED'
          raise NeedsReview,'The earlier publish response is uncertain. Reconcile this container in Meta before resubmission.' if %w[publishing_request needs_review].include?(state['phase'])
          # Persist before this non-idempotent request. A timeout must never
          # trigger a second publish of the same container.
          save_state!('phase'=>'publishing_request')
          media=graph("#{account}/media_publish",{'creation_id'=>container}).fetch('id').to_s
          raise ArgumentError,'Instagram returned an invalid media reference' unless media.match?(/\A[0-9]+\z/)
          save_state!('phase'=>'published','media_id'=>media)
          {'status'=>'published','remote_id'=>media}
        when 'PUBLISHED'
          save_state!('phase'=>'published')
          {'status'=>'published','remote_id'=>state['media_id'] || container}
        when 'ERROR','EXPIRED'
          save_state!('phase'=>'failed','provider_status'=>result['status_code'])
          raise ArgumentError,"Instagram container #{result['status_code'].downcase}; inspect its reference"
        else
          raise NeedsReview,'Instagram returned an unknown container state; reconcile its reference'
        end
      rescue StandardError=>error
        uncertain!(error)
      end
    end
  end
end
