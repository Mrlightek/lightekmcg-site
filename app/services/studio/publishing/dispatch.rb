module Studio
  module Publishing
    class Dispatch
      def initialize(publication)
        @publication = publication
      end

      def call
        Studio::Gatekeeper::Client.authorize!(
          capability: "studio.publish.#{publication.platform}",
          subject: publication,
          context: {
            project_id: publication.studio_project_id,
            production_id: publication.production_id,
            artifact_id: publication.artifact_id,
            platform: publication.platform
          }.compact
        )

        publication.update!(status: "publishing", error_message: nil)
        result = Studio::Publishers::Registry.fetch(publication.platform).new(publication).call
        publication.update!(status: "published", published_at: Time.current)
        result
      rescue StandardError => error
        publication&.update(status: "failed", error_message: error.message.to_s.first(2_000))
        raise
      end

      private

      attr_reader :publication
    end
  end
end
