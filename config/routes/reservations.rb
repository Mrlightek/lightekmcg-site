  get '/reservations', to: 'reservations#catalog', as: :reservations_catalog
  get '/reservations/slots', to: 'reservations#slots'
  resources :my_reservations, path: '/my/reservations', controller: 'reservations', only: %i[index show create] do
    member do
      post :checkout
      post :cancel
      patch :reschedule
      post :quote
      post :accept_change
      get :calendar
    end
  end
  get '/dashboard/reservations', to: 'dashboard/reservations#index', as: :dashboard_reservations
  post '/dashboard/reservations/experiences', to: 'dashboard/reservations#save_resource', as: :save_resource_dashboard_reservations
  post '/dashboard/reservations/blackouts', to: 'dashboard/reservations#blackout', as: :blackout_dashboard_reservations
  delete '/dashboard/reservations/blackouts/:id', to: 'dashboard/reservations#remove_blackout', as: :remove_blackout_dashboard_reservations
  post '/dashboard/reservations/:id/transition', to: 'dashboard/reservations#transition', as: :transition_dashboard_reservation
  patch '/dashboard/commerce/payout-schedule', to: 'dashboard/commerce_payouts#schedule', as: :dashboard_commerce_payout_schedule

  post '/dashboard/reservations/bookings', to: 'dashboard/reservations#create_booking', as: :book_dashboard_reservations
  post '/dashboard/reservations/changes/:id/retry', to: 'dashboard/reservations#retry_change', as: :retry_change_dashboard_reservation
