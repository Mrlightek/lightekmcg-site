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

      def self.schedule_weekly!(starts_at:, occurrences:, **options)
        count = Integer(occurrences.presence || "1", 10)
        raise ArgumentError, "Choose between 1 and 12 weekly airings." unless count.between?(1, 12)
        raise ArgumentError, "Enter a valid airtime." unless starts_at

        transaction do
          Array.new(count) { |week| schedule!(starts_at: starts_at.advance(weeks: week), **options) }
        end
      end

      def self.schedule!(channel:, operator:, title:, starts_at:, relay:, rows:, show_project_id: nil, measurement: {}, replay: false)
        raise ArgumentError, "Choose a Live Studio playout channel." unless channel.managed_playout? && channel.status != "off_air"
        raise ArgumentError, "Set airtime at least two minutes ahead so the media can be prepared." unless starts_at && starts_at >= 2.minutes.from_now
        raise ArgumentError, "Add between 1 and 40 rundown rows." unless rows.length.between?(1, 40)
        if relay && (channel.status != "published" || !%w[tiktok restream].include?(relay) || !Studio::Live::Destination.configured?(operator, provider: relay))
          raise ArgumentError, "Save this destination in Live Studio before scheduling it."
        end
        actor = Studio::PwaAccess.new("user_id" => operator.id, "site_id" => channel.site_id)
        assets = StudioAsset.for_actor(actor).where(site_id: channel.site_id, kind: "video", status: "ready")
        rundown = rows.map do |row|
          selection = row.fetch("asset_id")
          if (match = /\Alicense-(\d+)\z/.match(selection.to_s))
            raise ArgumentError, "Use licensed programming in a show segment on your managed channel." if relay || row["kind"] != "segment" || row["ad_campaign_id"].present?
            license = ProgramLicense.where(licensee_site_id: channel.site_id, status: "accepted").find(match[1])
            HostedPrograms.check_booking!(license) if license.imported?
            asset = license.asset || raise(ArgumentError, "That licensed program is unavailable.")
          else
            asset = assets.find(selection)
          end
          raise ArgumentError, "Choose a video with an available Studio proxy." unless asset.proxy.attached?
          type = row.fetch("kind")
          raise ArgumentError, "Choose a rundown slot type." unless SLOT_TYPES.key?(type)
          available = asset.metadata["duration"].to_f.floor
          if row["ad_campaign_id"].present?
            raise ArgumentError, "Choose an ad break for the network campaign." unless Advertising::Campaign::BREAKS.include?(type)
            campaign = Advertising::Campaign.for_station(channel.site_id).find(row["ad_campaign_id"])
            duration = campaign.seconds
            raise ArgumentError, "Choose a backup video long enough to fill the ad break." if duration > available
          else
            duration = row["seconds"].present? ? Integer(row["seconds"], 10) : available
            raise ArgumentError, "Each row must run for at least two seconds and fit its video." unless duration.between?(2, available)
          end
          label = row["label"].to_s.strip.presence || asset.name
          { "kind" => type, "label" => label.first(120), "asset_id" => asset.id, "blob_id" => asset.proxy.blob.id,
            "seconds" => duration, "sponsor" => row["sponsor"].to_s.squish.first(80), "ad_campaign_id" => campaign&.id,
            "license_id" => license&.id, "license_use" => ("replay" if replay && license) }.compact
        end
        duration = rundown.sum { |item| item.fetch("seconds") }
        raise ArgumentError, "A rundown can run up to two hours." if duration > 2.hours.to_i
        ends_at = starts_at + duration
        channel.with_lock do
          if channel.airings.where(status: ACTIVE).where("starts_at < ? AND ends_at > ?", ends_at, starts_at).exists?
            raise ArgumentError, "This airtime overlaps another rundown on the channel."
          end
          license_ids = rundown.filter_map { |item| item["license_id"] }.uniq
          licenses = ProgramLicense.where(licensee_site_id: channel.site_id, id: license_ids).order(:id).lock.to_a
          commercial = rundown.any? { |item| item["ad_campaign_id"].present? || item["sponsor"].present? }
          unless licenses.size == license_ids.size && licenses.all? { |license| license.broadcast_allowed?(starts_at, ends_at, replay: replay, commercial: commercial) }
            raise ArgumentError, "The license must cover the rundown window, both managed-channel platforms, worldwide delivery, and any commercial use."
          end
          airing = channel.airings.create!(operator: operator, title: title.to_s.strip, starts_at: starts_at,
            ends_at: ends_at, relay: relay, rundown: rundown, measurement: AudienceReport.normalize_metadata(measurement))
          if rundown.any? { |item| item["ad_campaign_id"] }
            producer = StudioProject.where(site_id: channel.site_id).find(show_project_id).owner if show_project_id.present?
            Advertising::Placement.book!(airing: airing, rows: rundown, producer: producer)
          end
          airing
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
            update!(state: state.except("input_segment", "ad_progress").merge("input" => input.id))
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
