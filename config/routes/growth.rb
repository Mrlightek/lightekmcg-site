get '/g/:token', to: 'growth_links#show', as: :growth_link
get '/feature-videos/:token/:position.mp4', to: 'feature_showcase_videos#show', as: :feature_showcase_video, constraints: {position: /[0-5]/}
get '/dashboard/marketing-copilot/showcases/:id/videos/:position', to: 'dashboard/marketing_copilot#video', as: :preview_dashboard_feature_video
get '/feature-videos/:token/:position/screenshots/:attachment_id', to: 'feature_showcase_videos#screenshot',
  as: :feature_showcase_screenshot, constraints: { position: /[0-5]/, attachment_id: /[0-9]+/ }
get '/dashboard/marketing-copilot/showcases/:id/screenshots/:position/:attachment_id', to: 'dashboard/marketing_copilot#screenshot',
  as: :preview_dashboard_feature_screenshot
delete '/dashboard/marketing-copilot/showcases/:id/screenshots/:position/:attachment_id', to: 'dashboard/marketing_copilot#remove_screenshot',
  as: :remove_dashboard_feature_screenshot
post '/dashboard/marketing-copilot/showcases/:id/screenshots/:position', to: 'dashboard/marketing_copilot#save_screenshot',
  as: :save_dashboard_feature_screenshot
post '/dashboard/marketing-copilot/showcases/:id/promotion', to: 'dashboard/marketing_copilot#prepare_demo_promotion',
  as: :prepare_dashboard_demo_promotion
post '/dashboard/marketing-copilot/showcases/:id/approve', to: 'dashboard/marketing_copilot#approve_showcase', as: :approve_dashboard_feature_showcase
post '/dashboard/marketing-copilot/:id/execute', to: 'dashboard/marketing_copilot#execute', as: :execute_dashboard_marketing_kit
get '/dashboard/growth', to: 'dashboard/growth#index', as: :dashboard_growth
get '/dashboard/marketing-copilot', to: 'dashboard/marketing_copilot#index', as: :dashboard_marketing_copilot
post '/dashboard/marketing-copilot', to: 'dashboard/marketing_copilot#create', as: :prepare_dashboard_marketing_kit
post '/dashboard/marketing-copilot/:id/check-in', to: 'dashboard/marketing_copilot#check_in', as: :check_in_dashboard_marketing_kit
post '/dashboard/marketing-copilot/:id/follow-up', to: 'dashboard/marketing_copilot#follow_up', as: :follow_up_dashboard_marketing_kit
patch '/dashboard/growth/brief', to: 'dashboard/growth#brief', as: :dashboard_growth_brief
post '/dashboard/growth/links', to: 'dashboard/growth#create_link', as: :dashboard_growth_links
patch '/dashboard/growth/links/:id', to: 'dashboard/growth#toggle', as: :dashboard_growth_link
post '/dashboard/growth/plans', to: 'dashboard/growth#prepare_plan', as: :prepare_dashboard_growth_plan
patch '/dashboard/growth/plans/:plan_id/steps/:id/resolve', to: 'dashboard/growth#resolve_step', as: :resolve_dashboard_growth_step
post '/dashboard/growth/plans/:plan_id/steps/:id/draft', to: 'dashboard/growth#draft_step', as: :draft_dashboard_growth_step
get '/dashboard/growth/search', to: 'dashboard/search_growth#show', as: :dashboard_search_growth
post '/dashboard/growth/search/sync', to: 'dashboard/search_growth#sync', as: :sync_dashboard_search_growth
post '/dashboard/growth/search/backlinks', to: 'dashboard/search_growth#record', as: :record_dashboard_search_backlink
post '/dashboard/growth/search/backlinks/import', to: 'dashboard/search_growth#import', as: :import_dashboard_search_backlinks
post '/dashboard/growth/search/backlinks/:id/draft', to: 'dashboard/search_growth#draft', as: :draft_dashboard_search_backlink
