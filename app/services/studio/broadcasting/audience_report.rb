# frozen_string_literal: true

require "csv"

module Studio
  module Broadcasting
    class AudienceReport
      INPUT_FIELDS = %i[asset_id program episode_title episode_id originator_id full_episode ad_load_type].freeze
      AD_TYPES = { "pre_roll" => "preroll", "mid_roll" => "midroll" }.freeze
      REQUIRED_FIELDS = INPUT_FIELDS - [:originator_id]
      HEADERS = %w[utc_day station_id outlet_id channel_id airing_id ad_row platform playback_sessions requested_segments requested_media_seconds].freeze

      def self.normalize_metadata(values)
        input = values.to_h.stringify_keys.slice(*INPUT_FIELDS.map(&:to_s)).transform_values { |value| value.to_s.squish }.compact_blank
        if input.any? { |_key, value| value.length > 120 } ||
            (input["asset_id"] && !input["asset_id"].match?(/\A[A-Za-z0-9]{1,48}\z/)) ||
            (input["full_episode"] && !%w[y n].include?(input["full_episode"])) ||
            (input["ad_load_type"] && !%w[1 2].include?(input["ad_load_type"]))
          raise ArgumentError, "Check the audience measurement IDs and selections."
        end
        input
      end

      def initialize(site:, start_day:, end_day:, outlet:)
        @site, @days, @outlet = site, start_day..end_day, outlet
        raise ArgumentError, "Choose a range of up to 31 days." unless (end_day - start_day).between?(0, 30)
      end

      def totals
        scope.pick(Arel.sql("COUNT(DISTINCT session_key)"), Arel.sql("COALESCE(SUM(segments), 0)"), Arel.sql("COALESCE(SUM(media_ms), 0)"))
      end

      def channel_totals
        scope.group(:channel_id).order(Arel.sql("SUM(media_ms) DESC"), :channel_id).limit(100).pluck(
          :channel_id, Arel.sql("COUNT(DISTINCT session_key)"), Arel.sql("SUM(media_ms)"))
      end

      def breakdown
        dimensions = %i[day station_site_id outlet_site_id channel_id airing_id ad_row platform]
        scope.group(*dimensions).order(*dimensions).pluck(*dimensions,
          Arel.sql("COUNT(*)"), Arel.sql("SUM(segments)"), Arel.sql("SUM(media_ms)"))
      end

      def csv
        CSV.generate do |file|
          file << HEADERS
          breakdown.each do |row|
            row[-1] = format("%.3f", row[-1] / 1000.0)
            row[5] = row[5].negative? ? nil : row[5] + 1
            file << row
          end
        end
      end

      def measurement_metadata
        time_window = utc_midnight(@days.begin)...utc_midnight(@days.end + 1)
        ids = scope.distinct.pluck(:airing_id)
        # A broadcaster may export metadata for its own airings with no measured activity.
        airings = if @outlet
          Airing.where(id: ids)
        else
          Airing.where(channel_id: Channel.where(site_id: @site.id).select(:id)).where(starts_at: time_window)
        end
        airings.includes(:channel).order(:starts_at).map { |airing| metadata_for(airing) }
      end

      private

      def scope
        ViewSession.where(day: @days, (@outlet ? :outlet_site_id : :station_site_id) => @site.id)
      end

      def utc_midnight(date) = Time.utc(date.year, date.month, date.day)

      def metadata_for(airing)
        values = airing.measurement
        fields = REQUIRED_FIELDS.dup
        fields << :originator_id if @outlet && airing.channel.site_id != @site.id
        started = airing.state["public_started_at"]
        aired = started && airing.events.any? { |event| event["type"] == "row_aired" }
        measured = scope.where(airing_id: airing.id).exists?
        {
          airing_id: airing.id, channel_id: airing.channel_id, station_site_id: airing.channel.site_id,
          scheduled_utc: airing.starts_at.utc.iso8601, as_aired_utc: (Time.iso8601(started).utc.iso8601 if aired),
          missing: fields.reject { |field| values[field.to_s].present? }.map(&:to_s) + (aired && measured ? [] : ["measured_airtime"]),
          content: {
            type: "content", assetid: values["asset_id"], program: values["program"], title: values["episode_title"],
            length: 0, airdate: (Time.iso8601(started).utc.strftime("%Y%m%d %H:%M:%S") if aired),
            crossId1: values["episode_id"], crossId2: values["originator_id"], isfullepisode: values["full_episode"],
            adloadtype: values["ad_load_type"]
          }.compact,
          network_ad_insertions: ad_insertions_for(airing)
        }
      end

      def ad_insertions_for(airing)
        ::Studio::Advertising::Placement.delivered.where(airing_id: airing.id).includes(:campaign).order(:row_index).map do |placement|
          slot = airing.rundown.fetch(placement.row_index)
          reference = placement.campaign.exchange_key || "campaign-#{placement.campaign_id}"
          {
            row: placement.row_index + 1, aired_through_utc: placement.delivered_at.utc.iso8601,
            duration_seconds: slot.fetch("seconds"), campaign_reference: reference,
            measurement: { type: AD_TYPES.fetch(slot.fetch("kind"), "ad"), assetid: "AD#{reference.delete('-')}" }
          }
        end
      end
    end
  end
end
