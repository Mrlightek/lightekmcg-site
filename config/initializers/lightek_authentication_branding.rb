# frozen_string_literal: true
Rails.application.routes.prepend do
  get "/dashboard/website/account-branding", to: "dashboard/authentication_branding#edit", as: :dashboard_authentication_branding
  patch "/dashboard/website/account-branding", to: "dashboard/authentication_branding#update"
end
