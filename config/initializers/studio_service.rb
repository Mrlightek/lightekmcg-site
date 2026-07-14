# frozen_string_literal: true
# Registers the Studio domain service with the kernel.
Rails.application.config.to_prepare do
  Lightek::ServiceRegistry.register(:studio, DymondStudio::StudioService)
end
