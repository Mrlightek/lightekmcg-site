get '/dashboard/sales', to: 'dashboard/sales#index', as: :dashboard_sales
get '/dashboard/sales/:kind/new', to: 'dashboard/sales#new', as: :new_dashboard_sales_record
post '/dashboard/sales/:kind', to: 'dashboard/sales#create', as: :dashboard_sales_records
get '/dashboard/sales/:kind/:id', to: 'dashboard/sales#show', as: :dashboard_sales_record
patch '/dashboard/sales/:kind/:id', to: 'dashboard/sales#update'
post '/dashboard/sales/lead/:id/convert', to: 'dashboard/sales#convert', as: :convert_dashboard_sales_lead
post '/dashboard/sales/:kind/:id/activities', to: 'dashboard/sales#activity', as: :dashboard_sales_activities
