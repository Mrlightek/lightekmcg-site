module Studio
  module Publishers
    class TikTok < Base
      def call
        credentials!(slug: "tiktok-studio-production")
        raise NotConfigured, "TikTok publishing adapter contract exists; API transport is not wired yet"
      end
    end
  end
end
