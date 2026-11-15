get '/g/:token', to: 'growth_links#show', as: :growth_link
get '/dashboard/growth', to: 'dashboard/growth#index', as: :dashboard_growth
patch '/dashboard/growth/brief', to: 'dashboard/growth#brief', as: :dashboard_growth_brief
post '/dashboard/growth/links', to: 'dashboard/growth#create_link', as: :dashboard_growth_links
patch '/dashboard/growth/links/:id', to: 'dashboard/growth#toggle', as: :dashboard_growth_link
post '/dashboard/growth/plans', to: 'dashboard/growth#prepare_plan', as: :prepare_dashboard_growth_plan
patch '/dashboard/growth/plans/:plan_id/steps/:id/resolve', to: 'dashboard/growth#resolve_step', as: :resolve_dashboard_growth_step
post '/dashboard/growth/plans/:plan_id/steps/:id/draft', to: 'dashboard/growth#draft_step', as: :draft_dashboard_growth_step
