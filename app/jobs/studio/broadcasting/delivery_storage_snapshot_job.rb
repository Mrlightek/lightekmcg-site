# frozen_string_literal: true

require "find"

module Studio
  module Broadcasting
    class DeliveryStorageSnapshotJob < ApplicationJob
      queue_as :default

      def perform
        day = Time.current.utc.to_date
        airings = PlayoutMedia.root.join("airings")
        stored_ids = airings.directory? ? airings.children.map { |path| path.basename.to_s }.grep(/\A[0-9]+\z/) : []
        Channel.where(managed_playout: true).find_each do |channel|
          paths = [PlayoutMedia.channel_path(channel.id)]
          paths.concat(channel.airings.where(id: stored_ids).pluck(:id).map { |id| PlayoutMedia.airing_path(id) })
          bytes = paths.sum do |path|
            next 0 unless path.directory?

            Find.find(path.to_s, ignore_error: true).sum do |name|
              metadata = File.lstat(name)
              metadata.file? ? metadata.size : 0
            rescue Errno::ENOENT
              0
            end
          end
          DeliveryUsage.upsert_all([{ site_id: channel.site_id, channel_key: channel.id.to_s, day: day,
            stored_bytes: bytes }], unique_by: :idx_broadcast_delivery_usage, update_only: [:stored_bytes])
        end
      end
    end
  end
end
