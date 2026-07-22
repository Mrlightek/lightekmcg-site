# frozen_string_literal: true
# Registers the Catalog domain service with the kernel.
Rails.application.config.to_prepare do
  Lightek::ServiceRegistry.register(:catalog, DymondCatalog::CatalogService)
end
