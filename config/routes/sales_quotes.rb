get '/sales/quotes/:token', to: 'sales_quotes#show', as: :public_sales_quote
post '/sales/quotes/:token/accept', to: 'sales_quotes#accept', as: :accept_public_sales_quote
get '/sales/quotes/:token/checkout', to: 'sales_quotes#embedded_checkout', as: :embedded_public_sales_quote
post '/sales/quotes/:token/checkout', to: 'sales_quotes#checkout', as: :checkout_public_sales_quote
post '/dashboard/sales/quotes', to: 'dashboard/sales_quotes#create', as: :dashboard_sales_quotes
get '/dashboard/sales/quotes/:id', to: 'dashboard/sales_quotes#show', as: :dashboard_sales_quote
post '/dashboard/sales/quotes/:id/issue', to: 'dashboard/sales_quotes#issue', as: :issue_dashboard_sales_quote
post '/dashboard/sales/quotes/:id/accept', to: 'dashboard/sales_quotes#accept', as: :accept_dashboard_sales_quote
