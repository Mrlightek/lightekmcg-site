# frozen_string_literal: true

module Studio
  module Advertising
    class ExchangeJob < ApplicationJob
      queue_as :default

      def perform(id)
        placement = Placement.find_by(id: id)
        return unless placement&.locally_exchanged? && placement.sync_after?

        # Persist the retry deadline before calling the exchange. A duplicate
        # sweep job reloads the same slot identity and skips this attempt.
        placement.with_lock do
          return unless placement.sync_after && placement.sync_after <= Time.current
          placement.update!(sync_after: 2.minutes.from_now)
        end
        Exchange.sync_placement!(placement)
      rescue Exchange::Unavailable, LightekReservations::Federation::Client::Unavailable => error
        Rails.logger.warn("[BroadcastAds] placement=#{id} exchange=#{error.class}")
      end
    end
  end
end
