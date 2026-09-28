module Studio
  module Providers
    class Registry
      PROVIDERS = {
        "blender" => "Studio::Providers::BlenderProvider"
      }.freeze

      def self.fetch(name)
        class_name = PROVIDERS.fetch(name.to_s) do
          raise KeyError, "Unknown Studio provider: #{name.inspect}"
        end
        class_name.constantize
      end
    end
  end
end
