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
get '/dashboard/sales/:kind/new', to: 'dashboard/sales#new', as: :new_dashboard_sales_record
post '/dashboard/sales/:kind', to: 'dashboard/sales#create', as: :dashboard_sales_records
get '/dashboard/sales/:kind/:id', to: 'dashboard/sales#show', as: :dashboard_sales_record
patch '/dashboard/sales/:kind/:id', to: 'dashboard/sales#update'
post '/dashboard/sales/lead/:id/convert', to: 'dashboard/sales#convert', as: :convert_dashboard_sales_lead
post '/dashboard/sales/:kind/:id/activities', to: 'dashboard/sales#activity', as: :dashboard_sales_activities
