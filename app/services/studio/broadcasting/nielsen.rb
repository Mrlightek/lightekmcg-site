# frozen_string_literal: true

module Studio
  module Broadcasting
    module Nielsen
      CONSUMER = name.freeze
      PURPOSE = "nielsen_measurement"
      APP_ID = /\AP?[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i
      module_function

      def browser_configuration(site)
        credential = configuration(site, "web")
        { app_id: credential[:app_id], debug: credential[:certification] } if credential
      end

      def roku_configuration(site)
        credential = configuration(site, "roku")
        return unless credential

        { app_id: credential[:app_id], mode: credential[:certification] ? "certification" : "production" }
      end

      def configuration(site, platform)
        slug = "nielsen-dcr-#{platform}-#{site.id}"
        return unless defined?(LightekVault::Secret) && LightekVault::Secret.exists?(slug: slug, status: "active")

        # This App ID is a public SDK identifier. Other Vault fields remain server-side.
        credential = LightekVault::Service.checkout!(slug: slug, consumer: CONSUMER, purpose: PURPOSE, requested_by: "broadcast-player")
        app_id = credential["app_id"].to_s
        environment = credential["environment"]
        return unless credential["enabled"] == true && APP_ID.match?(app_id) && %w[certification production].include?(environment)

        { app_id: app_id, certification: environment == "certification" }
      rescue LightekVault::Service::AccessDenied, LightekVault::MasterKey::ConfigurationError,
        LightekVault::Crypto::DecryptionError, ActiveRecord::RecordNotFound
        nil
      end

      def timeline(channel, distributor:)
        paths = PlayoutMedia.channel_path(channel.id).glob("out-*.json").sort_by { |path| path.basename.to_s[/\d+/].to_i }.last(35)
        records = paths.filter_map { |path| read_segment(path) }
        airings = channel.airings.where(id: records.pluck("airing_id")).index_by(&:id)
        records.filter_map do |segment|
          airing = airings[segment["airing_id"]]
          next unless airing
          content = content_for(airing, distributor: distributor)
          next unless content

          started_at = Time.iso8601(segment.fetch("aired_at")).to_f
          entry = { segment: segment["segment"], from: started_at, to: started_at + segment.fetch("media_ms") / 1000.0, content: content }
          entry[:ad] = segment["ad"] if segment["ad"].is_a?(Hash)
          if airing.measurement["roku_genre"].present? && content[:adloadtype] == "2"
            entry[:roku] = content.merge(program: content.fetch(:program).first(25), title: content.fetch(:title).first(25),
              progen: airing.measurement["roku_genre"], hasAds: airing.rundown.any? { |row| row["ad_campaign_id"] } ? "1" : "0")
          end
          entry
        end
      end

      def read_segment(path)
        data = JSON.parse(path.read)
        if data.is_a?(Hash) && data["media_ms"].is_a?(Integer) && data["aired_at"].is_a?(String)
          data.merge("segment" => path.basename(".json").to_s + ".ts")
        end
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      def content_for(airing, distributor:)
        values = airing.measurement
        required = AudienceReport::REQUIRED_FIELDS.map(&:to_s)
        required << "originator_id" if distributor
        return unless required.all? { |field| values[field].present? } && airing.state["public_started_at"]

        {
          type: "content", assetid: values["asset_id"], assetName: values["program"].first(100),
          program: values["program"].first(100), title: values["episode_title"].first(100), length: "0", section: "LiveTV",
          airdate: Time.iso8601(airing.state.fetch("public_started_at")).utc.strftime("%Y%m%d %H:%M:%S"),
          crossId1: values["episode_id"], crossId2: values["originator_id"], isfullepisode: values["full_episode"],
          adloadtype: values["ad_load_type"]
        }.compact
      end

      def ad_for(campaign, kind)
        key = campaign.exchange_key || "campaign#{campaign.id}"
        { type: AudienceReport::AD_TYPES.fetch(kind, "ad"), assetid: "AD#{key.delete('-')}" }
      end
    end
  end
end
