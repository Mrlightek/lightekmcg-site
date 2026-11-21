# frozen_string_literal: true

module Studio
  module Broadcasting
    class PrepareChannelBackupJob < ApplicationJob
      queue_as :playout_prepare

      def perform(channel_id, asset_id, blob_id)
        channel = Channel.find_by(id: channel_id, managed_playout: true)
        PlayoutMedia.prepare_backup!(channel, asset_id, blob_id) if channel
      end
    end
  end
end
