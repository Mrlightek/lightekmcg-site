Rails.application.routes.draw do
  post "/dashboard/marketing/campaigns/:id/send_email", to: "dashboard/marketing_campaigns#send_email", as: :send_dashboard_marketing_campaign
  resources :dashboard_marketing_campaigns, path: "/dashboard/marketing/campaigns", controller: "dashboard/marketing_campaigns", except: %i[show]
  post "/dashboard/marketing/campaigns/:id/send_audience", to: "dashboard/marketing_campaigns#send_audience", as: :send_dashboard_marketing_audience
  resources :dashboard_agency_memberships, path: "/dashboard/agency/memberships", controller: "dashboard/agency_memberships", only: %i[index create destroy]
  resources :dashboard_marketing_contacts, path: "/dashboard/marketing/contacts", controller: "dashboard/marketing_contacts", only: %i[index create]
  post "/marketing/subscribe", to: "marketing_subscriptions#create", as: :marketing_subscribe
  get "/marketing/confirm", to: "marketing_subscriptions#confirm", as: :confirm_marketing_subscription
  get "/marketing/unsubscribe", to: "marketing_subscriptions#unsubscribe", as: :unsubscribe_marketing_subscription
  get "/dashboard/agency/reports", to: "dashboard/agency_reports#index", as: :dashboard_agency_reports
  post "/dashboard/marketing/campaigns/:id/schedule", to: "dashboard/marketing_campaigns#schedule", as: :schedule_dashboard_marketing_campaign
  get "/dashboard/business", to: "dashboard/business_hub#index", as: :dashboard_business_hub
  post "/dashboard/commerce/shop_page", to: "dashboard/commerce_products#create_shop_page", as: :dashboard_commerce_shop_page
  resources :dashboard_commerce_products, path: "/dashboard/commerce/products", controller: "dashboard/commerce_products", except: %i[show]
  post "/commerce/stripe/webhook", to: "commerce_stripe_webhooks#create", as: :commerce_stripe_webhook
  post "/dashboard/commerce/orders/:order_id/refund", to: "dashboard/commerce_refunds#create", as: :dashboard_commerce_refund
  post "/dashboard/commerce/industry", to: "dashboard/commerce_products#install_industry", as: :dashboard_commerce_industry
  get "/commerce/shop", to: "commerce#index", as: :commerce_shop
  post "/commerce/cart", to: "commerce#add", as: :commerce_cart_add
  delete "/commerce/cart/:product_id", to: "commerce#remove", as: :commerce_cart_remove
  post "/commerce/checkout", to: "commerce#checkout", as: :commerce_checkout
  get "/dashboard/commerce/orders", to: "dashboard/commerce_orders#index", as: :dashboard_commerce_orders
  # BEGIN LIGHTEK MARKETPLACE V8.7
  get "/marketplace", to: "marketplace#index", as: :marketplace
  get "/marketplace/:id", to: "marketplace#show", as: :marketplace_listing, constraints: { id: /[0-9]+/ }
  get "/dashboard/marketplace", to: "dashboard/marketplace#index", as: :dashboard_marketplace
  resources :dashboard_marketplace_listings, path: "/dashboard/marketplace/listings",
    controller: "dashboard/marketplace", only: %i[new create edit update], constraints: { id: /[0-9]+/ }
  get "/catalogs", to: redirect("/marketplace", status: 302), constraints: ->(request) { request.format.html? }
  get "/dashboard/marketplace/listings/:id/preview", to: "dashboard/marketplace#preview", as: :preview_dashboard_marketplace_listing, constraints: { id: /[0-9]+/ }
  resources :dashboard_marketplace_groups, path: "/dashboard/marketplace/groups", controller: "dashboard/marketplace_groups", except: %i[show destroy]
  resources :dashboard_marketplace_connections, path: "/dashboard/marketplace/connections", controller: "dashboard/marketplace_connections", except: %i[show destroy]
  # END LIGHTEK MARKETPLACE V8.7
  get "/api/studio/capabilities", to: "api/studio/capabilities#index", as: :api_studio_capabilities
  get "/employee/nevaeh/review_packets", to: "employee/nevaeh_review_packets#index", as: :employee_nevaeh_review_packets
  get "/employee/nevaeh/coverage", to: "employee/nevaeh_coverage#index", as: :employee_nevaeh_coverage
  get "/employee/nevaeh/acceptance_evidence", to: "employee/nevaeh_acceptance_evidence#index", as: :employee_nevaeh_acceptance_evidence
  get "/employee/nevaeh/reviewed_candidates", to: "employee/nevaeh_reviewed_candidates#index", as: :employee_nevaeh_reviewed_candidates
  post "/employee/nevaeh/reviewed_candidates", to: "employee/nevaeh_reviewed_candidates#create", as: :employee_nevaeh_reviewed_candidates_create
  get "/employee/nevaeh/ticket_drafts", to: "employee/nevaeh_ticket_drafts#index", as: :employee_nevaeh_ticket_drafts
  post "/employee/nevaeh/ticket_drafts", to: "employee/nevaeh_ticket_drafts#create", as: :employee_nevaeh_ticket_drafts_create

  # 7A.8L: local draft generator, no promotion or execution.
  get "/employee/nevaeh/generator", to: "employee/nevaeh_generator#index", as: :employee_nevaeh_generator
  post "/employee/nevaeh/generator", to: "employee/nevaeh_generator#create", as: :employee_nevaeh_generator_create

# 7A.8J: configuration drafts only; admin authorization and CSRF required.
get "/employee/nevaeh/config", to: "employee/nevaeh_configuration#index", as: :employee_nevaeh_configuration
post "/employee/nevaeh/config", to: "employee/nevaeh_configuration#create", as: :employee_nevaeh_configuration_create
post "/employee/nevaeh/config/:key/jobs", to: "employee/nevaeh_configuration#add_job", as: :employee_nevaeh_configuration_job, constraints: { key: /[a-z][a-z0-9._]*/ }

  # 7A.8I - read-only Nevaeh overview; existing employee auth applies.
  get "/employee/nevaeh", to: "employee/nevaeh_overview#index", as: :employee_nevaeh_overview

# Phase 7A.8E: read-only capability console; no write or execution routes.
get "/employee/nevaeh/capabilities", to: "employee/nevaeh_capabilities#index", as: :employee_nevaeh_capabilities
get "/employee/nevaeh/services", to: "employee/nevaeh_capabilities#services", as: :employee_nevaeh_services
# Capability keys contain dots; explicitly constrain the key to permit dotted identifiers.
get "/employee/nevaeh/capabilities/:key", to: "employee/nevaeh_capabilities#show", as: :employee_nevaeh_capability, constraints: { key: /[a-z0-9][a-z0-9._-]*/ }

  resources :departments
  resources :system_jobs
  resources :job_items
  resources :channels
  resources :shows
  resources :episodes
  resources :nevaehs
  resources :profiles
  resources :posts
  resources :communities
  get "/booking", to: "dymond_booking/booking#index"
  mount DymondBooking::Engine => "/booking"
  get "/kb", to: "dymond_kb/kb#index"
  mount DymondKb::Engine => "/kb"
  get "/catalog", to: "dymond_catalog/catalog#index"
  mount DymondCatalog::Engine => "/catalog"
  get "/studio", to: "dymond_studio/studio#index"
  mount DymondStudio::Engine => "/studio"
  resource :session
  resources :passwords, param: :token
  resources :storyline_world_communities
  resources :storyline_world_forges
  resources :storyline_arenas
  resources :storylines
  #resources :dashboards
  resources :supports, only: %i[index create] do
    member { patch :reply }
  end
  resources :stores
  resources :architectures
  resources :abouts
  resources :resellers
  resources :catalogs
  resources :homes
  
# ── Public site ──────────────────────────────────────────────────────────────
root "pages#home"

get  "about",    to: "pages#about"
get  "services", to: "pages#services"
get  "pricing",  to: "pages#pricing"
get  "contact",  to: "pages#contact"


get  "/susu/signup", to: "susu_registrations#new", as: :susu_signup
post "/susu/signup", to: "susu_registrations#create"
get  "/susu/invitations/:token/accept", to: "susu_invitations#accept", as: :accept_susu_invitation

# ── Susu public product surface ───────────────────────────────────────────────
get "susu",            to: "susu_public#home",       as: :susu
get "susu/pricing",    to: "susu_public#pricing",    as: :susu_pricing
get "susu/onboarding", to: "susu_public#onboarding", as: :susu_onboarding

# ── Gatekeeper ──────────────────────────────────────────────────────────────
#Gatekeeper webhook for Stripe

post "/susu_groups/:id/request_payout", to: "susu_groups#request_payout", as: :request_payout_susu_group

resources :susu_match_preferences, only: %i[index new create show destroy]


# ── Gatekeeper Infrastructure Control ────────────────────────────────────────
namespace :gatekeeper do
  post "callbacks/github_deployment", to: "callbacks#github_deployment", as: :github_deployment_callback
  get "infrastructure", to: "infrastructure#index", as: :infrastructure
  resources :nodes
  resources :projects do
    member do
      post :deploy
      post :deploy_github
      post :healthcheck
    end
  end
end

# ── Susu ───────────────────────────────────────────────────────
resources :susu_groups do
  member do
    post :activate
    post :request_exit
    get  :contribution
    post :contribute
  end

  resources :susu_memberships, only: %i[create update destroy]
end

# ── Rails 8 native auth ───────────────────────────────────────────────────────
# Generated by: rails generate authentication
resources :sessions,      only: %i[new create destroy]
resources :registrations, only: %i[new create]
get  "sign_in",  to: "sessions#new",      as: :sign_in
get  "sign_up",  to: "registrations#new", as: :sign_up
delete "sign_out", to: "sessions#destroy", as: :sign_out

# ── Client portal ──────────────────────────────────────────────────────────────
namespace :portal do
  root "dashboard#index"
  resources :projects, only: %i[index show new create]
  resources :deliverables, only: %i[index show]
  resources :messages, only: %i[index create]
  resources :services, only: %i[index]
end

# ── Employee portal ────────────────────────────────────────────────────────────
namespace :employee do
    resources :users, only: %i[index new create edit update destroy]
    resources :tickets, only: %i[index show new create] do
      member { patch :reply; patch :resolve; post :execute_nevaeh }
    end
  root "dashboard#index"
  resources :clients,   only: %i[index show]
  resources :projects,  only: %i[index show edit update]
  resources :timesheets, only: %i[index create]
end

# ── Gatekeeper — Lightek client contract ──────────────────────────────────────
# Gatekeeper is the public experience/API contract for Roku and future clients.
get "gatekeeper",
  to: "gatekeeper#index",
  defaults: { format: :json },
  as: :gatekeeper

get "gatekeeper/config",
  to: "gatekeeper#platform_config",
  defaults: { format: :json },
  as: :gatekeeper_config

get "gatekeeper/content/:id",
  to: "gatekeeper#content",
  defaults: { format: :json },
  as: :gatekeeper_content

get "gatekeeper/screens/live",
  to: "gatekeeper#live",
  defaults: { format: :json },
  as: :gatekeeper_live

get "gatekeeper/search",
  to: "gatekeeper#search",
  defaults: { format: :json },
  as: :gatekeeper_search


# ── Community preview ──────────────────────────────────────────────
    
    get "preview/community", 
        to: "community_preview#index"

    get "preview/community/topic",
        to: "community_preview#topic"

    get "preview/community/discussion",
        to: "community_preview#discussion"

    get "preview/community/new",
        to: "community_preview#new"

    get "preview/community/profile",
        to: "community_preview#profile"

    get "preview/community/admin",
        to: "community_preview#admin"


# ── Dymond CMS engine — main admin/ops dashboard ──────────────────────────────
  # Lightek human control plane
  get "/dashboard/infrastructure",
      to: "dashboard/infrastructure#index",
      as: :dashboard_infrastructure

  get "/dashboard/susu",
      to: "dashboard/susu#index",
      as: :dashboard_susu

post "/dashboard/susu/payout-account/connect", to: "susu_payout_accounts#connect", as: :connect_dashboard_susu_payout_account
get "/dashboard/susu/payout-account/refresh", to: "susu_payout_accounts#refresh", as: :refresh_dashboard_susu_payout_account
get "/dashboard/susu/payout-account", to: "susu_payout_accounts#show", as: :dashboard_susu_payout_account

get "/dashboard/network", to: "dashboard/network#index", as: :dashboard_network
post "/dashboard/network/dns", to: "dashboard/network#create_dns", as: :dashboard_network_dns
put "/dashboard/network/dns", to: "dashboard/network#update_dns"
delete "/dashboard/network/dns", to: "dashboard/network#destroy_dns"
post "/dashboard/network/firewall/open", to: "dashboard/network#open_port", as: :dashboard_network_open_port
post "/dashboard/network/firewall/close", to: "dashboard/network#close_port", as: :dashboard_network_close_port

get "/dashboard/vault", to: "dashboard/vault#index", as: :dashboard_vault
post "/dashboard/vault", to: "dashboard/vault#create"
post "/dashboard/vault/disable", to: "dashboard/vault#disable", as: :dashboard_vault_disable

resources :dashboard_compute_providers, path: "/dashboard/infrastructure/providers", controller: "dashboard/compute_providers", only: %i[index show new create] do
  member do
    post :healthcheck
    post :activate
    post :disable
  end
end

get "/dashboard/infrastructure/catalog", to: "dashboard/infrastructure_catalog#index", as: :dashboard_infrastructure_catalog
post "/dashboard/infrastructure/profiles", to: "dashboard/infrastructure_catalog#create_profile", as: :dashboard_infrastructure_profiles
post "/dashboard/infrastructure/policies", to: "dashboard/infrastructure_catalog#create_policy", as: :dashboard_infrastructure_policies

# V8.6D: customer subscription administration (read-only contract discovery).
resources :dashboard_subscriptions,
          path: "/dashboard/subscriptions",
          controller: "dashboard/subscriptions",
          only: %i[index show],
          constraints: { id: /[0-9]+/ }
# V8_6E_ADMIN_CANCEL: Bank lifecycle cancellation
post "/dashboard/subscriptions/:id/cancel", to: "dashboard/subscriptions#cancel", as: :cancel_dashboard_subscription, constraints: { id: /[0-9]+/ }

resources :dashboard_subscription_plans,
          path: "/dashboard/subscriptions/plans",
          controller: "dashboard/subscription_plans"

patch "/dashboard/infrastructure/providers/:compute_provider_id/capabilities",
      to: "dashboard/compute_provider_capabilities#update",
      as: :dashboard_compute_provider_capabilities

resources :dashboard_provisioning_requests,
          path: "/dashboard/infrastructure/provisioning",
          controller: "dashboard/provisioning_requests",
          only: %i[index show create] do
  member do
    post :configure
    post :approve
    post :reject
    post :execute
    post :verify
    post :approve_destroy
    post :destroy
  end
end

post "/dashboard/infrastructure/providers/:compute_provider_id/validate",
     to: "dashboard/compute_provider_validations#create",
     as: :validate_dashboard_compute_provider

post "/dashboard/infrastructure/providers/:compute_provider_id/linode_smoke_test",
     to: "dashboard/linode_smoke_tests#create",
     as: :dashboard_linode_smoke_test

get "/dashboard/bank", to: "dashboard/financial_operations#index", as: :dashboard_bank

  # BEGIN LIGHTEK ORGANIZED SETTINGS
  get "/dashboard/settings", to: "dashboard/settings_home#index", as: :dashboard_settings_home
  get "/dashboard/settings/general", to: "dashboard/platform_settings#index", as: :dashboard_platform_settings
  patch "/dashboard/settings/general", to: "dashboard/platform_settings#update"
  patch "/dashboard/settings", to: "dashboard/platform_settings#update"
  get "/dashboard/website/settings", to: "dashboard/website_settings#show", as: :dashboard_website_settings
  patch "/dashboard/website/settings", to: "dashboard/website_settings#update"
  # END LIGHTEK ORGANIZED SETTINGS

# BEGIN LIGHTEK WEBSITE DESIGNS
  get "/dashboard/website/designs", to: "dashboard/website_designs#index", as: :dashboard_website_designs
  get "/dashboard/website/designs/preview", to: "dashboard/website_designs#preview", as: :preview_dashboard_website_designs
  post "/dashboard/website/designs/apply", to: "dashboard/website_designs#apply", as: :apply_dashboard_website_designs
  post "/dashboard/website/designs/import", to: "dashboard/website_designs#import", as: :import_dashboard_website_designs
  patch "/dashboard/website/designs/fonts", to: "dashboard/website_designs#update_fonts", as: :fonts_dashboard_website_designs
# END LIGHTEK WEBSITE DESIGNS

# BEGIN LIGHTEK DESIGN STUDIO
  get "/dashboard/design-studio", to: "dashboard/design_studio#index", as: :dashboard_design_studio_index
  post "/dashboard/design-studio", to: "dashboard/design_studio#create", as: :create_dashboard_design_studio
  get "/dashboard/design-studio/:id/edit", to: "dashboard/design_studio#edit", as: :edit_dashboard_design_studio
  patch "/dashboard/design-studio/:id", to: "dashboard/design_studio#update", as: :dashboard_design_studio
  delete "/dashboard/design-studio/:id", to: "dashboard/design_studio#destroy", as: :delete_dashboard_design_studio
  post "/dashboard/design-studio/:id/preview", to: "dashboard/design_studio#preview", as: :preview_dashboard_design_studio
  post "/dashboard/design-studio/:id/publish", to: "dashboard/design_studio#publish", as: :publish_dashboard_design_studio
  post "/dashboard/design-studio/:id/upload", to: "dashboard/design_studio#upload", as: :upload_dashboard_design_studio
# END LIGHTEK DESIGN STUDIO


# Browser-based live production. Uses the existing authenticated /cable endpoint.
scope "/dashboard/mail", controller: "dashboard/mail_studio" do
  get "/", action: :index, as: :dashboard_mail
  post "/domains", action: :create_domain, as: :dashboard_mail_domains
  post "/domains/:id/verify", action: :verify_domain, as: :verify_dashboard_mail_domain
  post "/accounts", action: :create_account, as: :dashboard_mail_accounts
  patch "/accounts/:account_id", action: :configure_account, as: :dashboard_mail_account
  post "/accounts/:account_id/token", action: :token, as: :dashboard_mail_token
  get "/accounts/:account_id/compose", action: :compose, as: :compose_dashboard_mail
  post "/accounts/:account_id/messages", action: :create_message, as: :dashboard_mail_messages
  get "/accounts/:account_id/messages/:id", action: :show_message, as: :dashboard_mail_message
  post "/accounts/:account_id/messages/:id/send", action: :send_draft, as: :send_dashboard_mail_message
  patch "/accounts/:account_id/messages/:id/flag", action: :flag_message, as: :flag_dashboard_mail_message
  delete "/accounts/:account_id/messages/:id", action: :purge_message, as: :purge_dashboard_mail_message
  get "/accounts/:account_id/messages/:id/attachments/:attachment_id", action: :attachment, as: :dashboard_mail_attachment
  get "/accounts/:account_id/templates/new", action: :edit_template, as: :new_dashboard_mail_template
  get "/accounts/:account_id/templates/:id/export", action: :export_template, as: :export_dashboard_mail_template
  get "/accounts/:account_id/templates/:id/edit", action: :edit_template, as: :edit_dashboard_mail_template
  post "/accounts/:account_id/templates", action: :save_template, as: :dashboard_mail_templates
  patch "/accounts/:account_id/templates/:id", action: :save_template, as: :dashboard_mail_template
  post "/accounts/:account_id/templates/preview", action: :preview_template, as: :preview_dashboard_mail_template
end
post "/api/lightek-mail/messages", to: "api/lightek_mail#create"
get "/api/lightek-mail/messages/:id", to: "api/lightek_mail#show"
post "/api/lightek-mail/inbound", to: "api/lightek_mail#inbound"
post "/api/lightek-mail/feedback", to: "api/lightek_mail#feedback"

get "/dashboard/live", to: "dashboard/live_broadcasts#index", as: :dashboard_live
post "/dashboard/live/sessions", to: "dashboard/live_broadcasts#create", as: :dashboard_live_sessions
post "/dashboard/live/destination", to: "dashboard/live_broadcasts#destination", as: :dashboard_live_destination
get "/dashboard/live/:id/recording", to: "dashboard/live_broadcasts#recording", as: :dashboard_live_recording, constraints: {id: /[0-9]+/}

  get "/dashboard/system_logs", to: "dashboard/system_logs#index", as: :dashboard_system_logs
  mount DymondDash::Engine => "/dashboard"

# ── DymondBank — billing, invoices, subscriptions ─────────────────────────────
mount DymondBank::Engine => "/billing"

# Uncomment as gems are added:
# mount DymondSocial::Engine  => "/social"
# mount LightekStudio::Engine => "/studio"
# mount DymondConnect::Engine => "/connect"

# ── Health check (Kamal / load balancer) ──────────────────────────────────────
get "up", to: "rails/health#show", as: :rails_health_check

# ── PWA ───────────────────────────────────────────────────────────────────────
get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
get "manifest"       => "rails/pwa#manifest",       as: :pwa_manifest



  get "/api/nevaeh/bootstrap",
      to: "api/nevaeh#bootstrap"


  post "/api/nevaeh/payment_quote",
       to: "api/nevaeh/payment_quotes#create"


  post "/api/nevaeh/execute",
       to: "api/nevaeh#execute"

end
