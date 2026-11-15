# frozen_string_literal: true
require 'net/http'
require 'json'
require 'uri'
module Studio
  module Publishers
    class SocialTransport < Base
      class Pending < StandardError; end
      class NeedsReview < StandardError; end
      def self.connection!(id,actor:,project:)
        Studio::Broadcasting::Access.authorize!(actor.reload,project.site)
        Studio::PwaAccess.new('user_id'=>actor.id,'site_id'=>project.site_id).projects.find(project.id)
        LightekMarketing::SocialConnection.where(site_id:project.site_id,enabled:true).find(id)
      end
      def self.http!(uri,token,values={},method: :post)
        raise ArgumentError,'Unsupported social API host' unless uri.scheme=='https' && %w[open.tiktokapis.com graph.facebook.com].include?(uri.host) && !uri.userinfo
        request=if method==:get
          uri=uri.dup;uri.query=URI.encode_www_form(values)
          Net::HTTP::Get.new(uri.request_uri)
        else
          Net::HTTP::Post.new(uri.request_uri).tap { |r| r['Content-Type']='application/json';r.body=values.to_json }
        end
        request['Authorization']="Bearer #{token}"
        response=Net::HTTP.start(uri.host,uri.port,use_ssl:true,open_timeout:5,read_timeout:30,write_timeout:30) { |http| http.request(request) }
        raise ArgumentError,'Social provider returned an oversized response' if response.body.to_s.bytesize>500_000
        data=JSON.parse(response.body)
        code=data.dig('error','code')
        raise ArgumentError,"Social API rejected the request (HTTP #{response.code}, code #{code.to_s.gsub(/[^a-zA-Z0-9_-]/,'').first(80)})" unless response.is_a?(Net::HTTPSuccess) && (!data['error'] || code=='ok')
        data
      rescue JSON::ParserError
        raise ArgumentError,'Social provider returned an invalid response'
      end
      def connection
        @connection ||= begin
          actor=User.find(publication.metadata.fetch('user_id'))
          record=self.class.connection!(publication.metadata.fetch('connection_id'),actor:actor,project:publication.studio_project)
          raise ArgumentError,'The connected account belongs to a different destination' unless record.provider==publication.platform
          record
        end
      end
      def credentials
        @credentials ||= LightekMarketing::SocialVault.checkout!(connection:connection)
      end
      def state = publication.reload.metadata.fetch('social_submission',{})
      def save_state!(values)
        publication.with_lock do
          publication.update!(metadata:publication.metadata.merge('social_submission'=>publication.metadata.fetch('social_submission',{}).merge(values).merge('updated_at'=>Time.current.iso8601)))
        end
      end
      def confirm_review!(allow_uncertain:false)
        connection
        raise ArgumentError,'Review the video and select its social destination before publishing' unless publication.metadata['reviewed']==true || publication.metadata['director_reviewed_at']
        raise ArgumentError,'Choose a completed MP4 video from this project' unless publication.artifact.kind=='video' && publication.artifact.file.attached? && publication.artifact.file.blob.content_type=='video/mp4' && publication.artifact.studio_operation&.studio_project_id==publication.studio_project_id && publication.artifact.studio_operation.status=='completed'
        raise ArgumentError,'Reconnect and reconcile the earlier social request before retrying' if !allow_uncertain && %w[requesting publishing_request needs_review].include?(state['phase'])
      end
      def video_url
        host=publication.studio_project.site.host.to_s
        raise ArgumentError,'The site needs a public host before social delivery' unless host.match?(/\A[a-zA-Z0-9.-]+\z/) && host.include?('.')
        Rails.application.routes.url_helpers.rails_blob_url(publication.artifact.file,host:host,protocol:'https',disposition:'inline')
      end
      def duration
        Studio::MediaProcess.temporary_directory('social-duration-') do |root|
          path=File.join(root,'video.mp4')
          File.open(path,'wb') { |file| publication.artifact.file.blob.download { |chunk| file.write(chunk) } }
          command=['ffprobe','-v','error','-show_entries','format=duration','-of','json',path]
          command=Studio::MediaProcess.container(command.map { |arg| arg.gsub(root,'/work') },root:root,image:Studio::NativeBlender::Runtime.image(:media)) if Rails.env.production?
          Float(JSON.parse(Studio::MediaProcess.run!(command,timeout:30)).fetch('format').fetch('duration'))
        end
      end
      def uncertain!(error)
        save_state!('phase'=>'needs_review') if %w[requesting publishing_request].include?(state['phase'])
        raise NeedsReview,'The provider response is uncertain. Reconcile this request before submitting again.' if state['phase']=='needs_review'
        raise error
      end
      def caption
        [publication.metadata['title'],publication.metadata['content']].compact.join("\n\n")
      end
    end
  end
end
