Rails.application.config.to_prepare do
  LightekAgency::PackageLimits.install_callbacks!
end
