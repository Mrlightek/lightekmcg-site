# frozen_string_literal: true
Rails.application.config.to_prepare do
  if defined?(Lightek::ServiceRegistry) && defined?(DymondSite::SiteService)
    Lightek::ServiceRegistry.register(:site, DymondSite::SiteService)
  end
end
