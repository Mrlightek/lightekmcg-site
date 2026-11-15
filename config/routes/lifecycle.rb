get '/dashboard/people/lifecycle', to: 'dashboard/lifecycle#index', as: :dashboard_lifecycle
post '/dashboard/people/lifecycle', to: 'dashboard/lifecycle#start', as: :start_dashboard_lifecycle
post '/dashboard/people/lifecycle/:id/step', to: 'dashboard/lifecycle#step', as: :step_dashboard_lifecycle
post '/dashboard/people/lifecycle/:id/revoke', to: 'dashboard/lifecycle#revoke', as: :revoke_dashboard_lifecycle
post '/dashboard/people/lifecycle/:id/complete', to: 'dashboard/lifecycle#complete', as: :complete_dashboard_lifecycle
post '/dashboard/people/lifecycle/:id/cancel', to: 'dashboard/lifecycle#cancel', as: :cancel_dashboard_lifecycle
