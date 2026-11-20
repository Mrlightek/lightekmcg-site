# frozen_string_literal: true

module Studio
  module Broadcasting
    class PlayoutSweepJob < ApplicationJob
      def perform
        now = Time.current
        Airing.where(status: %w[preparing ready], ends_at: ..now).update_all(status: "failed", updated_at: now, error_message: "The rundown missed its airtime.")
        Airing.where(status: "ready", starts_at: ..(now + Playout::LEAD))
          .or(Airing.where(status: "on_air", updated_at: ..(now - 20.seconds)))
          .distinct.pluck(:channel_id).each { |id| ChannelPlayoutJob.perform_later(id) }
        Airing.where(status: "preparing", updated_at: ..(now - 2.minutes)).limit(30).pluck(:id).each do |id|
          PrepareAiringJob.perform_later(id)
        end
        PlayoutMedia.root.join("airings").glob("*").each do |path|
          next unless path.basename.to_s.match?(/\A\d+\z/) && path.mtime < 1.hour.ago
          next if Airing.where(id: path.basename.to_s, status: Airing::ACTIVE).exists?
          FileUtils.remove_entry_secure(path)
        end
      end
    end
  end
end
