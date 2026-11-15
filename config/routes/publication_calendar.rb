get '/campaign-media/:token/:filename', to: 'campaign_media#show', as: :campaign_media, format: false, constraints: {filename: /[^\/]+/}
get '/dashboard/publication-calendar', to: 'dashboard/publication_calendar#index', as: :dashboard_publication_calendar
post '/dashboard/publication-calendar', to: 'dashboard/publication_calendar#create'
post '/dashboard/publication-calendar/media', to: 'dashboard/publication_calendar#attach_media', as: :attach_campaign_media
patch '/dashboard/publication-calendar/media/:id/revoke', to: 'dashboard/publication_calendar#revoke_media', as: :revoke_campaign_media
patch '/dashboard/publication-calendar/:id/cancel', to: 'dashboard/publication_calendar#cancel', as: :cancel_publication_slot
