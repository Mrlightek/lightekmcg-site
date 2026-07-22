# frozen_string_literal: true
# Registers the Kb domain service with the kernel.
Rails.application.config.to_prepare do
  Lightek::ServiceRegistry.register(:kb, DymondKb::KbService)
end
