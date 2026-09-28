module Studio
  module Publishers
    class LightekSocial < Base
      def call
        raise NotConfigured, "Lightek Social publishing adapter is reserved for the native social platform"
      end
    end
  end
end
