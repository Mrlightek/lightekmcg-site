get '/request-demo', to: 'demo_requests#new', as: :request_demo
post '/request-demo', to: 'demo_requests#create'
get '/request-demo/confirm/:token', to: 'demo_requests#show', as: :confirm_demo_request
post '/request-demo/confirm/:token', to: 'demo_requests#activate', as: :activate_demo_request
resources :dashboard_demos, path: '/dashboard/demos', controller: 'dashboard/demos', only: %i[index create show] do
  patch :settings, on: :collection
  post :upgrade, on: :member
end

get '/dashboard/reseller-packages', to: 'dashboard/reseller_packages#index', as: :dashboard_reseller_packages
post '/dashboard/reseller-packages', to: 'dashboard/reseller_packages#create'

resources :dashboard_agency_trials, path: '/dashboard/agency-trials', controller: 'dashboard/agency_trials',
  only: %i[index create show update] do
  post :upgrade, on: :member
  post :resend, on: :member
  patch :publish, on: :collection
end

get '/request-agency-demo', to: 'agency_trial_requests#new', as: :request_agency_demo
post '/request-agency-demo', to: 'agency_trial_requests#create'
get '/request-agency-demo/confirm/:token', to: 'agency_trial_requests#show', as: :confirm_agency_demo
post '/request-agency-demo/confirm/:token', to: 'agency_trial_requests#activate'
