# frozen_string_literal: true
# Register dymond_site's universal capability with the Lightek kernel.
# Guarded so a missing kernel never breaks boot.
Rails.application.config.to_prepare do
  if defined?(Lightek::CapabilityRegistry) && defined?(DymondSite::Capability)
    Lightek::CapabilityRegistry.register(DymondSite::Capability)
  end
end
