# frozen_string_literal: true

module Studio
  module Broadcasting
    class Airing < ApplicationRecord
      self.table_name = "studio_channel_airings"
      SLOT_TYPES = {
        "pre_roll" => "Pre-roll", "segment" => "Show segment", "mid_roll" => "Mid-roll",
        "pre_end_roll" => "Pre-end roll", "close" => "Close"
      }.freeze
      ACTIVE = %w[preparing ready on_air].freeze
      RETURN_MODES = %w[resume clock next].freeze

      belongs_to :channel, class_name: "Studio::Broadcasting::Channel"
      belongs_to :operator, class_name: "User"
      validates :title, presence: true, length: { maximum: 120 }
      validates :relay, inclusion: { in: %w[tiktok restream] }, allow_nil: true
      validates :status, inclusion: { in: ACTIVE + %w[completed failed cancelled] }
      validates :starts_at, :ends_at, presence: true

      def self.schedule!(channel:, operator:, title:, starts_at:, relay:, rows:)
        raise ArgumentError, "Choose a Live Studio playout channel." unless channel.managed_playout? && channel.status != "off_air"
        raise ArgumentError, "Set airtime at least two minutes ahead so the media can be prepared." unless starts_at && starts_at >= 2.minutes.from_now
        raise ArgumentError, "Add between 1 and 40 rundown rows." unless rows.length.between?(1, 40)
        if relay && (channel.status != "published" || !%w[tiktok restream].include?(relay) || !Studio::Live::Destination.configured?(operator, provider: relay))
          raise ArgumentError, "Save this destination in Live Studio before scheduling it."
        end
        actor = Studio::PwaAccess.new("user_id" => operator.id, "site_id" => channel.site_id)
        assets = StudioAsset.for_actor(actor).where(site_id: channel.site_id, kind: "video", status: "ready")
        rundown = rows.map do |row|
          asset = assets.find(row.fetch("asset_id"))
          raise ArgumentError, "Choose a video with an available Studio proxy." unless asset.proxy.attached?
          type = row.fetch("kind")
          raise ArgumentError, "Choose a rundown slot type." unless SLOT_TYPES.key?(type)
          available = asset.metadata["duration"].to_f.floor
          duration = row["seconds"].present? ? Integer(row["seconds"], 10) : available
          raise ArgumentError, "Each row must run for at least two seconds and fit its video." unless duration.between?(2, available)
          label = row["label"].to_s.strip.presence || asset.name
          { "kind" => type, "label" => label.first(120), "asset_id" => asset.id, "blob_id" => asset.proxy.blob.id,
            "seconds" => duration, "sponsor" => row["sponsor"].to_s.squish.first(80) }
        end
        duration = rundown.sum { |item| item.fetch("seconds") }
        raise ArgumentError, "A rundown can run up to two hours." if duration > 2.hours.to_i
        ends_at = starts_at + duration
        channel.with_lock do
          if channel.airings.where(status: ACTIVE).where("starts_at < ? AND ends_at > ?", ends_at, starts_at).exists?
            raise ArgumentError, "This airtime overlaps another rundown on the channel."
          end
          channel.airings.create!(operator: operator, title: title.to_s.strip, starts_at: starts_at,
            ends_at: ends_at, relay: relay, rundown: rundown)
        end
      end

      def position = state.fetch("position", 0).to_f

      def row_at(position)
        boundary = 0
        rundown.each_with_index do |item, index|
          ending = boundary + item.fetch("seconds")
          return [index, position - boundary, ending] if position < ending
          boundary = ending
        end
        nil
      end

      def command!(action, input: nil)
        with_lock do
          case action
          when "cancel"
            raise ArgumentError, "Only upcoming rundowns can be cancelled." unless status.in?(%w[preparing ready])
            update!(status: "cancelled")
          when "break"
            raise ArgumentError, "The rundown must be on air and have no active cut-in." unless status == "on_air" && !state["input"]
            update!(state: state.except("input_segment").merge("input" => input.id))
          when *RETURN_MODES
            raise ArgumentError, "There is no live cut-in to return from." unless status == "on_air" && state["input"]
            target = case action
            when "resume" then position
            when "clock" then [Time.current - starts_at, 0].max
            when "next" then row_at(position)&.last || position
            end
            update!(state: state.except("input", "input_segment").merge("position" => target, "return" => action, "generation" => state.fetch("generation", 0) + 1))
          else
            raise ArgumentError, "Choose an available playout control."
          end
        end
      end

      def record_event!(event, details = {})
        self.events += [details.merge("type" => event, "at" => Time.current.iso8601)]
      end
    end
  end
end
