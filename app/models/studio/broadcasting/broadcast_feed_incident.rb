# frozen_string_literal: true

module Studio
  module Broadcasting
    class BroadcastFeedIncident < ApplicationRecord
      self.table_name = "studio_broadcast_feed_incidents"
      belongs_to :hosted_carriage, class_name: "Studio::Broadcasting::HostedCarriage"

      def self.observe!(entry, source)
        entry.with_lock do
          previous = entry.observed_feed_state
          return if previous == source

          event = { "station" => "station_restored", "backup" => "backup_started", "unavailable" => "station_unavailable" }.fetch(source)
          create!(hosted_carriage: entry, event: event) unless previous.nil? && source == "station"
          entry.update_columns(observed_feed_state: source)
        end
      end
    end
  end
end
