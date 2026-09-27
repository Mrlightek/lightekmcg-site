module Gatekeeper
  module Compute
    class Registry
      BUILTINS = {
        "linode" => "Gatekeeper::Compute::Providers::LinodeAdapter",
        "ovh" => "Gatekeeper::Compute::Providers::OvhAdapter"
      }.freeze

      def self.build(provider, requested_by: "system", operation_id: nil)
        klass_name =
          case provider.adapter_type
          when "builtin"
            provider.adapter_class.presence || BUILTINS.fetch(provider.slug)
          when "declarative"
            "Gatekeeper::Compute::Providers::DeclarativeAdapter"
          else
            provider.adapter_class.presence || raise(ArgumentError, "Custom provider requires adapter_class")
          end

        klass_name.constantize.new(provider:, requested_by:, operation_id:)
      end
    end
  end
end
