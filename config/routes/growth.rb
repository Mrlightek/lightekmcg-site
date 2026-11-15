get '/g/:token', to: 'growth_links#show', as: :growth_link
get '/dashboard/growth', to: 'dashboard/growth#index', as: :dashboard_growth
patch '/dashboard/growth/brief', to: 'dashboard/growth#brief', as: :dashboard_growth_brief
post '/dashboard/growth/links', to: 'dashboard/growth#create_link', as: :dashboard_growth_links
patch '/dashboard/growth/links/:id', to: 'dashboard/growth#toggle', as: :dashboard_growth_link
