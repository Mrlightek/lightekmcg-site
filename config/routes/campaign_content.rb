get '/dashboard/campaigns/:campaign_id/content', to: 'dashboard/campaign_content#index', as: :dashboard_campaign_content
post '/dashboard/campaigns/:campaign_id/content', to: 'dashboard/campaign_content#generate', as: :generate_dashboard_campaign_content
patch '/dashboard/campaigns/:campaign_id/content/:id', to: 'dashboard/campaign_content#update', as: :dashboard_campaign_content_variant
post '/dashboard/campaigns/:campaign_id/content/:id/approve', to: 'dashboard/campaign_content#approve', as: :approve_dashboard_campaign_content_variant
post '/dashboard/campaigns/:id/studio-brief', to: 'dashboard/marketing_campaigns#sync_studio_brief', as: :sync_campaign_studio_brief
