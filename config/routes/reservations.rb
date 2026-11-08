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

  get '/network/reservations/:token', to: 'network_reservations#show', as: :network_reservation
  post '/network/reservations/:token', to: 'network_reservations#book', as: :book_network_reservation
  get '/my/resort-earnings', to: 'network_reservations#earnings', as: :resort_earnings
  patch '/my/resort-earnings', to: 'network_reservations#schedule', as: :resort_earnings_schedule
  get '/api/reservations/federation/catalog', to: 'api/reservation_federation#catalog'
  post '/api/reservations/federation/offers', to: 'api/reservation_federation#save_offer'
  post '/api/reservations/federation/intents', to: 'api/reservation_federation#intent'
  get '/api/reservations/federation/reservations/:subject', to: 'api/reservation_federation#reservations'
  get '/api/reservations/federation/payouts', to: 'api/reservation_federation#payouts'
  patch '/api/reservations/federation/payouts', to: 'api/reservation_federation#payouts'
  get '/dashboard/reservations/network', to: 'dashboard/reservations#network', as: :network_dashboard_reservations
  post '/dashboard/reservations/network/offers', to: 'dashboard/reservations#network_offer', as: :offer_network_dashboard_reservations
  patch '/dashboard/reservations/network/payouts', to: 'dashboard/reservations#network_payouts', as: :payouts_network_dashboard_reservations
  post '/dashboard/installations/:id/reservation-network', to: 'dashboard/installations#connect_reservations', as: :connect_reservations_dashboard_installation
