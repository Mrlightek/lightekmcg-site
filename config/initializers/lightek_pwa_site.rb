Rails.application.config.to_prepare do
  DymondSite::Site.include(LightekPwaSite) unless DymondSite::Site < LightekPwaSite
end
