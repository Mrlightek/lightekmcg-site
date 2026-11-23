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

post '/api/reservations/federation/installation/office/:operation', to: 'api/installation_collaboration#office',
  constraints: {operation: /list|show|create|update|history|live|sync|restore/}
get '/dashboard/team-network/office/:key', to: 'dashboard/network_office#index', as: :dashboard_network_office
post '/dashboard/team-network/office/:key', to: 'dashboard/network_office#save'
get '/dashboard/team-network/office/:key/export/:file_key', to: 'dashboard/network_office#export', as: :export_dashboard_network_office

scope '/dashboard/executive-work/items/:id/travel', controller: 'dashboard/executive_travel' do
  get '/', action: :index, as: :dashboard_executive_travel
  post '/supplier', action: :configure, as: :configure_executive_travel_supplier
  post '/search', action: :search, as: :search_executive_travel
  post '/hotel-rates', action: :rates, as: :rates_executive_travel
  post '/quotes', action: :quote, as: :quote_executive_travel
  post '/bookings/:booking_id', action: :book, as: :book_executive_travel
  post '/bookings/:booking_id/reconcile', action: :reconcile, as: :reconcile_executive_travel
end

scope '/dashboard/executive-work/items/:id/theater', controller: 'dashboard/executive_dcp' do
  get '/', action: :index, as: :dashboard_executive_dcp
  post '/', action: :create
  post '/:delivery_id/validate', action: :validate_package, as: :validate_executive_dcp
  delete '/:delivery_id', action: :revoke, as: :revoke_executive_dcp
end
scope '/dashboard/theater-delivery/:key', controller: 'dashboard/executive_dcp', constraints: {key: /[a-f0-9]{48}/} do
  get '/', action: :show, as: :dashboard_executive_dcp_delivery
  get '/download', action: :download, as: :download_executive_dcp_delivery
  post '/acknowledge', action: :acknowledge, as: :acknowledge_executive_dcp_delivery
end

scope '/dashboard/shared-drives', controller: 'dashboard/shared_drives' do
  get '/', action: :index, as: :dashboard_shared_drives
  post '/', action: :create
  get '/:id', action: :show, as: :dashboard_shared_drive
  post '/:id/add', action: :add, as: :add_dashboard_shared_drive
  post '/:id/grant', action: :grant, as: :grant_dashboard_shared_drive
  patch '/:id/entries/:entry_id', action: :organize, as: :organize_dashboard_shared_drive
  get '/:id/download/:entry_id', action: :download, as: :download_dashboard_shared_drive
end

scope '/dashboard/shared-drives/:drive_id/office', controller: 'dashboard/team_office' do
  get '/', action: :index, as: :dashboard_drive_office
  post '/', action: :create
  patch '/:file_id', action: :update, as: :update_dashboard_drive_office
  get '/:file_id/live', action: :live, as: :live_dashboard_drive_office
  post '/:file_id/restore', action: :restore, as: :restore_dashboard_drive_office
  get '/:file_id/export', action: :export, as: :export_dashboard_drive_office
end

resources :dashboard_shared_calendars, path: '/dashboard/shared-calendars', controller: 'dashboard/shared_calendars', only: %i[index show create] do
  post :schedule, on: :member
  patch 'events/:event_id', action: :reschedule, as: :reschedule, on: :member
  post 'events/:event_id/respond', action: :respond, as: :respond, on: :member
  post 'events/:event_id/cancel', action: :cancel, as: :cancel_event, on: :member
  get 'events/:event_id/ics', action: :ics, as: :event_ics, on: :member
end

get '/dashboard/team-chat/:channel_id/office/:file_id/live', to: 'dashboard/team_office#live', as: :live_dashboard_team_office
post '/dashboard/team-chat/:channel_id/office/:file_id/restore', to: 'dashboard/team_office#restore', as: :restore_dashboard_team_office
get '/dashboard/team-network/office/:key/live/:file_key', to: 'dashboard/network_office#live', as: :live_dashboard_network_office
post '/dashboard/team-network/office/:key/sync/:file_key', to: 'dashboard/network_office#sync', as: :sync_dashboard_network_office
post '/dashboard/team-network/office/:key/restore/:file_key', to: 'dashboard/network_office#restore', as: :restore_dashboard_network_office
