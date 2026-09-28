module Studio
  module Publishers
    class LightekStreaming < Base
      def call
        raise NotConfigured, "Lightek Streaming publishing adapter is reserved for the native OTT/media API"
      end
    end
  end
end
