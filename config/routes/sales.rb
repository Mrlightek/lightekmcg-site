get '/sales/inquiry', to: 'sales_inquiries#new', as: :sales_inquiry, format: false
post '/sales/inquiry', to: 'sales_inquiries#create', format: false
get '/dashboard/sales/prospecting', to: 'dashboard/sales_prospecting#index', as: :dashboard_sales_prospecting
post '/dashboard/sales/prospecting/connect', to: 'dashboard/sales_prospecting#connect', as: :connect_dashboard_sales_prospecting
post '/dashboard/sales/prospecting/authorize-x', to: 'dashboard/sales_prospecting#authorize_x', as: :authorize_x_dashboard_sales_prospecting
get '/dashboard/sales/prospecting/x/callback', to: 'dashboard/sales_prospecting#x_callback', as: :x_callback_dashboard_sales_prospecting
post '/dashboard/sales/prospecting/disconnect', to: 'dashboard/sales_prospecting#disconnect', as: :disconnect_dashboard_sales_prospecting
post '/dashboard/sales/prospecting/search', to: 'dashboard/sales_prospecting#search', as: :search_dashboard_sales_prospecting
post '/dashboard/sales/prospecting/save', to: 'dashboard/sales_prospecting#save', as: :save_dashboard_sales_prospecting
post '/dashboard/sales/prospecting/save-web', to: 'dashboard/sales_prospecting#save_web', as: :save_web_dashboard_sales_prospecting
post '/dashboard/sales/prospecting/cadences', to: 'dashboard/sales_prospecting#create_cadence', as: :cadences_dashboard_sales_prospecting
post '/dashboard/sales/prospecting/:id/message', to: 'dashboard/sales_prospecting#message', as: :message_dashboard_sales_prospect
post '/dashboard/sales/prospecting/:id/block', to: 'dashboard/sales_prospecting#block_contact', as: :block_contact_dashboard_sales_prospect
post '/dashboard/sales/prospecting/:id/outreach', to: 'dashboard/sales_prospecting#outreach', as: :outreach_dashboard_sales_prospect
post '/dashboard/sales/prospecting/:id/cadence', to: 'dashboard/sales_prospecting#apply_cadence', as: :cadence_dashboard_sales_prospect
post '/dashboard/sales/prospecting/:id/lead', to: 'dashboard/sales_prospecting#lead', as: :lead_dashboard_sales_prospect
get '/dashboard/sales/intake', to: 'dashboard/sales_intake#index', as: :dashboard_sales_intake
post '/dashboard/sales/intake/upload', to: 'dashboard/sales_intake#upload', as: :upload_dashboard_sales_intake
post '/dashboard/sales/intake/capture', to: 'dashboard/sales_intake#capture', as: :capture_dashboard_sales_intake
post '/dashboard/sales/intake/rules', to: 'dashboard/sales_intake#configure', as: :configure_dashboard_sales_intake
get '/dashboard/sales/intake/:id', to: 'dashboard/sales_intake#show', as: :dashboard_sales_intake_entry
post '/dashboard/sales/intake/:id/accept', to: 'dashboard/sales_intake#accept', as: :accept_dashboard_sales_intake
post '/dashboard/sales/intake/:id/ignore', to: 'dashboard/sales_intake#ignore', as: :ignore_dashboard_sales_intake
post '/dashboard/sales/tasks', to: 'dashboard/sales_tasks#schedule', as: :dashboard_sales_tasks
patch '/dashboard/sales/tasks/:id', to: 'dashboard/sales_tasks#change', as: :dashboard_sales_task
get '/dashboard/sales/tasks/:id/calendar', to: 'dashboard/sales_tasks#calendar', as: :calendar_dashboard_sales_task
get '/dashboard/sales', to: 'dashboard/sales#index', as: :dashboard_sales
get '/dashboard/sales/materials', to: 'dashboard/sales_partners#materials', as: :dashboard_sales_materials
get '/dashboard/sales/partners', to: 'dashboard/sales_partners#index', as: :dashboard_sales_partners
post '/dashboard/sales/partners', to: 'dashboard/sales_partners#create'
post '/dashboard/sales/partners/:id/revoke', to: 'dashboard/sales_partners#revoke', as: :revoke_dashboard_sales_partner
get '/sales/partner-payouts/:id', to: 'sales_partner_payouts#show', as: :sales_partner_payout_setup
post '/sales/partner-payouts/:id', to: 'sales_partner_payouts#create'
post '/dashboard/sales/partners/:id/payout-invitation', to: 'dashboard/sales_partners#invite_payout_setup', as: :invite_dashboard_sales_partner_payout
post '/dashboard/sales/partners/payout-sender/verify', to: 'dashboard/sales_partners#verify_payout_sender', as: :verify_dashboard_sales_payout_sender
post '/dashboard/sales/partners/:id/recipient', to: 'dashboard/sales_partners#link_recipient', as: :link_dashboard_sales_partner_recipient
post '/dashboard/sales/commissions/:id/prepare', to: 'dashboard/sales_partners#prepare_commission', as: :prepare_dashboard_sales_commission
post '/dashboard/sales/commission-payouts/:id/release', to: 'dashboard/sales_partners#release_commission', as: :release_dashboard_sales_commission_payout
post '/dashboard/sales/commission-payouts/:id/refresh', to: 'dashboard/sales_partners#refresh_commission', as: :refresh_dashboard_sales_commission_payout
post '/dashboard/sales/commissions/:id/receipt', to: 'dashboard/sales_partners#record_payout', as: :record_dashboard_sales_commission
get '/dashboard/sales/:kind/new', to: 'dashboard/sales#new', as: :new_dashboard_sales_record
post '/dashboard/sales/:kind', to: 'dashboard/sales#create', as: :dashboard_sales_records
get '/dashboard/sales/:kind/:id', to: 'dashboard/sales#show', as: :dashboard_sales_record
patch '/dashboard/sales/:kind/:id', to: 'dashboard/sales#update'
post '/dashboard/sales/lead/:id/convert', to: 'dashboard/sales#convert', as: :convert_dashboard_sales_lead
post '/dashboard/sales/:kind/:id/activities', to: 'dashboard/sales#activity', as: :dashboard_sales_activities
