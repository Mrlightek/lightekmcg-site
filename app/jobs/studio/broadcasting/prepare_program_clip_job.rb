# frozen_string_literal: true

module Studio
  module Broadcasting
    class PrepareProgramClipJob < ApplicationJob
      queue_as :playout_prepare

      def perform(clip_id)
        clip = ProgramClip.find_by(id: clip_id)
        clip&.prepare!
      rescue StandardError => error
        Rails.logger.warn("[StudioPlayout] clip=#{clip_id} error=#{error.class}")
        clip&.with_lock do
          clip.update!(error_message: "The clip could not be prepared. Check the source and current rights before trying again.") unless clip.video.attached? || clip.withdrawn_at?
        end
      end
    end
  end
end
