module Studio
  module Publishers
    class Facebook < Base
      def call
        credentials!(slug: "facebook-studio-production")
        raise NotConfigured, "Facebook publishing adapter contract exists; API transport is not wired yet"
      end
    end
  end
end
