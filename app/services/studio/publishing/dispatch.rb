module Studio
  module Publishing
    class Dispatch
      def initialize(publication)
        @publication = publication
      end

      def call
        claimed = false
        publication.with_lock do
          return if publication.status.in?(%w[published cancelled publishing])
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

        result = Studio::Publishers::Registry.fetch(publication.platform).new(publication).call
        publication.update!(status: "published", published_at: Time.current)
        result
      rescue StandardError => error
        publication.update(status: "failed", error_message: error.message.to_s.first(2_000)) if claimed
        raise
      end

      private

      attr_reader :publication
    end
  end
end
