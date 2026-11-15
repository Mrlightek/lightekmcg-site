module Studio
  module Publishing
    class Dispatch
      def initialize(publication)
        @publication = publication
      end

      def call
        claimed = false
        publication.with_lock do
          return if publication.status.in?(%w[published cancelled publishing needs_review])
          publication.update!(status: "publishing", error_message: nil)
          claimed = true
        end
        Studio::Gatekeeper::Client.authorize!(
          capability: %w[lightek_social lightek_streaming octavia].include?(publication.platform) ? "studio.workspace.artifact.publish" : "studio.publish.#{publication.platform}",
          subject: publication,
          context: {
            project_id: publication.studio_project_id,
            production_id: publication.production_id,
            artifact_id: publication.artifact_id,
            platform: publication.platform
          }.compact
        )

        if publication.metadata['director_assembly_id']
          actor = User.find(publication.metadata.fetch('user_id'))
          Studio::Director::Producer.find!(publication.production_id,actor:actor)
          assembly = publication.production.studio_operations.where(capability:'studio.direct.assemble',status:'completed').find(publication.metadata['director_assembly_id'])
          raise ArgumentError, 'The reviewed master changed' unless assembly.artifacts.exists?(id:publication.artifact_id)
          Studio::Director::Finishing.verify_sources!(assembly)
        end
        result = Studio::Publishers::Registry.fetch(publication.platform).new(publication).call
        if result.is_a?(Hash) && result['status']=='processing'
          StudioSocialPublicationPollJob.set(wait:1.minute).perform_later(publication.id)
        else
          publication.update!(status: "published", published_at: Time.current)
        end
        result
      rescue Studio::Publishers::SocialTransport::NeedsReview => error
        publication.update(status:'needs_review',error_message:error.message.to_s.first(1000)) if claimed
        raise
      rescue StandardError => error
        publication.update(status: "failed", error_message: error.message.to_s.first(2_000)) if claimed
        raise
      end

      private

      attr_reader :publication
    end
  end
end
