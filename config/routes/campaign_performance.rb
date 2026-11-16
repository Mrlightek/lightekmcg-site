get '/dashboard/growth/performance', to: 'dashboard/campaign_performance#index', as: :dashboard_campaign_performance
post '/dashboard/growth/performance', to: 'dashboard/campaign_performance#create'
post '/dashboard/growth/performance/:id/reviews', to: 'dashboard/campaign_performance#review', as: :review_dashboard_campaign_performance
post '/dashboard/growth/performance/reviews/:id/draft', to: 'dashboard/campaign_performance#draft', as: :draft_dashboard_campaign_performance
