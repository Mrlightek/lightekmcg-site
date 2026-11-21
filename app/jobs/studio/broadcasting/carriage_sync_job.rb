# frozen_string_literal: true

module Studio
  module Broadcasting
    class CarriageSyncJob < ApplicationJob
      def perform(id)
        entry = NetworkCarriage.find_by(id: id)
        InstallationCarriage.sync!(entry) if entry && entry.status != "withdrawn"
      rescue InstallationCarriage::Unavailable, LightekReservations::Federation::Client::Unavailable
        Rails.logger.warn("[BroadcastCarriage] sync_failed=#{id}")
      end
    end
  end
end
