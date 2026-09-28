module Studio
  module Publishers
    class Instagram < Base
      def call
        credentials!(slug: "instagram-studio-production")
        raise NotConfigured, "Instagram publishing adapter contract exists; API transport is not wired yet"
      end
    end
  end
end
