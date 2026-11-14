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
