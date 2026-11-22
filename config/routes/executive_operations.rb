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
