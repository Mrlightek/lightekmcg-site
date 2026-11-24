  get "/my/it-services/billing", to: "it_service_billing#index", as: :it_service_billing
  post "/my/it-services/billing/plans/:plan_id/checkout", to: "it_service_billing#checkout", as: :checkout_it_service_plan
  post "/my/it-services/billing/subscriptions/:id/cancel", to: "it_service_billing#cancel", as: :cancel_it_service_subscription
  get "/dashboard/it-services/finance", to: "dashboard/it_service_finance#index", as: :dashboard_it_service_finance
  post "/dashboard/it-services/finance/plans", to: "dashboard/it_service_finance#create_plan", as: :dashboard_it_service_plan
  post "/dashboard/it-services/finance/appointments", to: "dashboard/it_service_finance#mark_appointment", as: :dashboard_it_service_appointment
  post "/dashboard/it-services/finance/payouts", to: "dashboard/it_service_finance#prepare_payout", as: :dashboard_it_service_payout
