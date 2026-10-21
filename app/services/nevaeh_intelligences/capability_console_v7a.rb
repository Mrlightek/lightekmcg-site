# frozen_string_literal: true
module NevaehIntelligences
  module CapabilityConsoleV7a
    module_function

    def list(root: Rails.root.to_s)
      YamlCapabilityRegistryV7a.list(root: root)
    end

    def detail(root: Rails.root.to_s, key:)
      definition = YamlCapabilityRegistryV7a.read(root: root, key: key)
      map = if File.file?(File.join(root, "config/nevaeh/trusted_services.yml"))
        TrustedServiceCatalogV7a.paths(root: root)
      else
        {}
      end
      { "definition" => definition,
        "reconciliation" => CapabilityReconcilerV7a.plan(root: root, key: key, service_paths: map),
        "execution_allowed" => false }
    end

    def services(root: Rails.root.to_s)
      TrustedServiceCatalogV7a.inspect(root: root)
    end
  end
end
