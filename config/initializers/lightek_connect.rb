Rails.application.config.filter_parameters += [:code, :connect_code, :id_token, :external_identity, :client_secret]

Rails.application.config.to_prepare do
  controller = DymondDash::ApplicationController
  controller.include(LightekConnect::DelegatedSession) unless controller < LightekConnect::DelegatedSession
end
