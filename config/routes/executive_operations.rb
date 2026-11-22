get '/dashboard/nevaeh/agenda', to: 'dashboard/nevaeh_agenda#index', as: :dashboard_nevaeh_agenda
resources :dashboard_nevaeh_agenda_items, path: '/dashboard/nevaeh/agenda/items',
  controller: 'dashboard/nevaeh_agenda', only: %i[create update] do
  member do
    patch :close
    get :calendar
    post :invite
  end
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

get '/dashboard/executive-work', to: 'dashboard/executive_work#index', as: :dashboard_executive_work
post '/dashboard/executive-work', to: 'dashboard/executive_work#create'
resources :dashboard_executive_cases, path: '/dashboard/executive-work/items', controller: 'dashboard/executive_work', only: [] do
  member do
    post :route
    post :review
    post :close
    post :dispatch_material
    get :material
  end
end

get '/dashboard/team-chat/:channel_id/office', to: 'dashboard/team_office#index', as: :dashboard_team_office
post '/dashboard/team-chat/:channel_id/office', to: 'dashboard/team_office#create'
patch '/dashboard/team-chat/:channel_id/office/:file_id', to: 'dashboard/team_office#update', as: :update_dashboard_team_office
get '/dashboard/team-chat/:channel_id/office/:file_id/export', to: 'dashboard/team_office#export', as: :export_dashboard_team_office

post '/dashboard/executive-work/phone', to: 'dashboard/executive_work#configure_phone', as: :configure_dashboard_executive_phone
post '/api/executive/phone/:key', to: 'api/executive_phone#create', as: :executive_phone_intake, constraints: {key: /[a-f0-9]{48}/}
