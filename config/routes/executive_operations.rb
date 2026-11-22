get '/dashboard/nevaeh/agenda', to: 'dashboard/nevaeh_agenda#index', as: :dashboard_nevaeh_agenda
resources :dashboard_nevaeh_agenda_items, path: '/dashboard/nevaeh/agenda/items',
  controller: 'dashboard/nevaeh_agenda', only: %i[create update] do
  patch :close, on: :member
end

resources :dashboard_team_channels, path: '/dashboard/team-chat', controller: 'dashboard/team_channels', only: %i[index show create] do
  collection do
    post :share
    post :accept_share
  end
  member do
    delete :disconnect
    get :timeline
    post :messages
    post :invite
    delete :remove
  end
end

post '/api/reservations/federation/installation/team/:operation', to: 'api/installation_collaboration#team',
  constraints: {operation: /list|create|show|accept|disconnect|member|post/}
post '/api/reservations/federation/installation/mail/:operation', to: 'api/installation_collaboration#mail',
  constraints: {operation: /provision|inbox|read|send/}

get '/dashboard/team-network', to: 'dashboard/network_team#index', as: :dashboard_network_team
post '/dashboard/team-network/:operation', to: 'dashboard/network_team#change',
  as: :change_dashboard_network_team, constraints: {operation: /create|accept|disconnect|member|post/}

get '/dashboard/mail/installation', to: 'dashboard/installation_mail#index', as: :dashboard_installation_mail
post '/dashboard/mail/installation', to: 'dashboard/installation_mail#send_message'
