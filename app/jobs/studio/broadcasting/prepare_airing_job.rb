# frozen_string_literal: true

module Studio
  module Broadcasting
    class PrepareAiringJob < ApplicationJob
      queue_as :playout_prepare

      def perform(id)
        airing = Airing.find_by(id: id, status: "preparing")
        return unless airing
        PlayoutMedia.prepare!(airing)
        if airing.reload.status == "ready"
          ChannelPlayoutJob.set(wait_until: [Time.current, airing.starts_at - Playout::LEAD + 2.seconds].max).perform_later(airing.channel_id)
        end
      rescue StandardError => error
        Rails.logger.error("[StudioPlayout] prepare=#{id} error=#{error.class}")
        airing&.with_lock do
          airing.update!(status: "failed", error_message: "A rundown video could not be prepared. Check the source files and available disk space.") if airing.status == "preparing"
        end
      end
    end
  end
end
