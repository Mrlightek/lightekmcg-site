# frozen_string_literal: true

module Studio
  module Broadcasting
    class ChannelPlayoutJob < ApplicationJob
      queue_as :playout

      def perform(channel_id)
        channel = Channel.find_by(id: channel_id, managed_playout: true)
        Playout.new(channel).run if channel
      end
    end
  end
end
