get '/account/setup/:token/edit', to: 'account_setups#edit', as: :edit_account_setup
put '/account/setup/:token', to: 'account_setups#update', as: :account_setup
get '/identity/onboarding-status', to: 'identity_onboarding#show'
get '/identity/security', to: 'identity_security#show', as: :identity_security
post '/identity/security/enroll', to: 'identity_security#enroll', as: :enroll_identity_security
post '/identity/security/confirm', to: 'identity_security#confirm', as: :confirm_identity_security
post '/identity/security/disable', to: 'identity_security#disable', as: :disable_identity_security
get '/identity/challenge', to: 'identity_challenges#show', as: :identity_challenge
post '/identity/challenge', to: 'identity_challenges#create'
post '/identity/sso', to: 'identity_sso#create', as: :identity_sso
get '/identity/sso/callback', to: 'identity_sso#callback', as: :identity_sso_callback
get '/dashboard/directory', to: 'dashboard/directory#index', as: :dashboard_directory
post '/dashboard/directory/policy', to: 'dashboard/directory#policy', as: :dashboard_directory_policy
post '/dashboard/directory/connection', to: 'dashboard/directory#connection', as: :dashboard_directory_connection
post '/dashboard/directory/grants', to: 'dashboard/directory#grant', as: :dashboard_directory_grants
delete '/dashboard/directory/grants/:id', to: 'dashboard/directory#revoke', as: :dashboard_directory_grant
post '/dashboard/directory/realm', to: 'dashboard/directory#realm', as: :dashboard_directory_realm
post '/dashboard/directory/nodes/:id', to: 'dashboard/directory#join', as: :dashboard_directory_join
post '/dashboard/directory/applications/:id/retry', to: 'dashboard/directory#retry_application', as: :dashboard_directory_retry_application

get '/dashboard/compliance',to: 'dashboard/compliance#index',as: :dashboard_compliance
post '/dashboard/compliance',to: 'dashboard/compliance#create'
post '/dashboard/compliance/credentials',to: 'dashboard/compliance#credentials',as: :credentials_dashboard_compliance
post '/dashboard/compliance/:id/refresh',to: 'dashboard/compliance#refresh',as: :refresh_dashboard_compliance
delete '/dashboard/compliance/:id',to: 'dashboard/compliance#destroy',as: :dashboard_compliance_monitor

post '/dashboard/directory/members/:id',to: 'dashboard/directory#member',as: :dashboard_directory_member
