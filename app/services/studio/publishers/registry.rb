module Studio
  module Publishers
    class Registry
      PUBLISHERS = {
        "tiktok" => "Studio::Publishers::TikTok",
        "instagram" => "Studio::Publishers::Instagram",
        "facebook" => "Studio::Publishers::Facebook",
        "lightek_social" => "Studio::Publishers::LightekSocial",
        "lightek_streaming" => "Studio::Publishers::LightekStreaming"
      }.freeze

      def self.fetch(platform)
        PUBLISHERS.fetch(platform.to_s).constantize
      rescue KeyError
        raise KeyError, "Unknown Studio publication platform: #{platform.inspect}"
      end
    end
  end
end
