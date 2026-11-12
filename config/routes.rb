Rails.application.routes.draw do
  post "/dashboard/website/designs/themes", to: "dashboard/website_designs#install_theme", as: :dashboard_website_themes
  post "/dashboard/website/designs/themes/:template_id/activate", to: "dashboard/website_designs#activate_theme", as: :activate_dashboard_website_theme
  resources :blog, only: %i[index show], param: :slug, controller: "lightek_blog", as: :website_blog
  get "/journal.xml", to: "lightek_blog#feed", as: :website_blog_feed
  namespace :dashboard do
    resources :blog, only: %i[index create update], controller: "blog" do
      get :preview, on: :member
    end
  end
  draw :reservations
  post "/website/template-inquiries", to: "website_template_inquiries#create", as: :website_template_inquiries
  get "/dashboard/website/designs/manifest", to: "dashboard/website_designs#manifest", as: :dashboard_website_design_manifest
  get "/dashboard/website/designs/starter-preview", to: "dashboard/website_designs#starter_preview", as: :dashboard_website_starter_preview
  patch "/dashboard/website/designs/branding", to: "dashboard/website_designs#update_branding", as: :dashboard_website_design_branding
  post "/dashboard/website/designs/start", to: "dashboard/website_designs#start", as: :start_dashboard_website_design
  resources :studio_workstations,path:"/dashboard/studio/workstations",controller:"dashboard/studio_workstations",only:%i[create show destroy],as: :dashboard_studio_workstations do
    member do
      get :status
      post :ticket
      post :workspace
      post :save
    end
  end

  # Host Studio routes precede every engine mount.
  post "/dashboard/studio-broadcasting/execute", to: "dashboard/media_studio#workspace_execute", as: :dashboard_studio_execute
  post "/dashboard/studio-broadcasting/uploads", to: "dashboard/media_studio#workspace_upload", as: :dashboard_studio_upload
  get "/dashboard/studio-broadcasting/assets/:id/:flavor", to: "dashboard/media_studio#workspace_asset", as: :dashboard_studio_asset
  get "/dashboard/studio-broadcasting/workspace(/:scene_id)", to: "dashboard/media_studio#workspace", as: :dashboard_production_workspace
  get "/dashboard/studio-broadcasting", to: "dashboard/media_studio#index", as: :dashboard_media_studio
  post "/dashboard/studio-broadcasting/generation-provider", to: "dashboard/media_studio#save_generation_provider", as: :dashboard_studio_generation_provider
  post "/dashboard/studio-broadcasting/applications", to: "dashboard/media_studio#save_application", as: :dashboard_broadcast_applications
  patch "/dashboard/studio-broadcasting/applications/:id", to: "dashboard/media_studio#save_application", as: :dashboard_broadcast_application
  post "/dashboard/studio-broadcasting/channels", to: "dashboard/media_studio#save_channel", as: :dashboard_broadcast_channels
  patch "/dashboard/studio-broadcasting/channels/:id", to: "dashboard/media_studio#save_channel", as: :dashboard_broadcast_channel
  post "/dashboard/studio-broadcasting/programs", to: "dashboard/media_studio#schedule", as: :dashboard_broadcast_programs
  delete "/dashboard/studio-broadcasting/programs/:id", to: "dashboard/media_studio#remove_program", as: :dashboard_broadcast_program
  patch "/dashboard/studio-broadcasting/posts/:id", to: "dashboard/media_studio#update_post", as: :dashboard_broadcast_post
  post "/dashboard/studio-broadcasting/publications", to: "dashboard/media_studio#publish", as: :dashboard_broadcast_publications
  delete "/dashboard/studio-broadcasting/publications/:id", to: "dashboard/media_studio#cancel_publication", as: :dashboard_broadcast_publication
  post "/dashboard/studio-broadcasting/live/:id/stop", to: "dashboard/media_studio#stop_live", as: :stop_dashboard_broadcast
  get "/dashboard/pwa", to: "dashboard/pwa#show", as: :dashboard_pwa
  patch "/dashboard/pwa", to: "dashboard/pwa#update"
  post "/dashboard/pwa/hostname", to: "dashboard/pwa#repair_hostname", as: :dashboard_pwa_hostname
  patch "/dashboard/pwa/records/:kind/:id", to: "dashboard/pwa#moderate", as: :dashboard_pwa_record
  post "/dashboard/pwa/communities/:id/members", to: "dashboard/pwa#community_invite", as: :dashboard_pwa_community_members
  post "/dashboard/pwa/people", to: "dashboard/pwa#invite", as: :dashboard_pwa_people
  get "/dashboard/pwa/media/:kind/:id", to: "dashboard/pwa#media", as: :dashboard_pwa_media
  get "/api/lightek/pwa/manifest", to: "api/lightek_pwa#manifest"
  resources :installations, path: "/my/installations", only: %i[index show create] do
    post :access, on: :member
    post :cancel_subscription, on: :member
    post :retry_installation, on: :member, path: "resume"
  end
  get "/dashboard/installations", to: "dashboard/installations#index", as: :dashboard_installations
  post "/dashboard/installations/:id/resume", to: "dashboard/installations#retry_installation", as: :resume_dashboard_installation
  post "/dashboard/marketing/campaigns/:id/studio", to: "dashboard/marketing_campaigns#studio", as: :studio_dashboard_marketing_campaign
  post "/dashboard/marketing/campaigns/:id/send_email", to: "dashboard/marketing_campaigns#send_email", as: :send_dashboard_marketing_campaign
  resources :dashboard_marketing_campaigns, path: "/dashboard/marketing/campaigns", controller: "dashboard/marketing_campaigns", except: %i[show]
  post "/dashboard/marketing/campaigns/:id/send_audience", to: "dashboard/marketing_campaigns#send_audience", as: :send_dashboard_marketing_audience
  resources :dashboard_agency_memberships, path: "/dashboard/agency/memberships", controller: "dashboard/agency_memberships", only: %i[index create destroy]
  resources :dashboard_marketing_contacts, path: "/dashboard/marketing/contacts", controller: "dashboard/marketing_contacts", only: %i[index create]
  post "/marketing/subscribe", to: "marketing_subscriptions#create", as: :marketing_subscribe
  get "/marketing/confirm", to: "marketing_subscriptions#confirm", as: :confirm_marketing_subscription
  get "/marketing/unsubscribe", to: "marketing_subscriptions#unsubscribe", as: :unsubscribe_marketing_subscription
  post "/dashboard/agency/social/publication/retry", to: "dashboard/social_connections#retry_publication", as: :retry_dashboard_social_publication
  post "/dashboard/agency/social/submission/refresh", to: "dashboard/social_connections#refresh_submission", as: :refresh_dashboard_social_submission
  post "/dashboard/agency/social/test", to: "dashboard/social_connections#test_connection", as: :test_dashboard_social_connection
  post "/dashboard/agency/social/disable", to: "dashboard/social_connections#disable", as: :disable_dashboard_social_connection
  get "/dashboard/agency/social/meta/connect", to: "dashboard/meta_connections#start", as: :start_dashboard_meta_connection
  get "/dashboard/agency/social/meta/callback", to: "dashboard/meta_connections#callback", as: :callback_dashboard_meta_connection
  get "/dashboard/agency/social/tiktok/connect", to: "dashboard/tiktok_connections#start", as: :start_dashboard_tiktok_connection
  get "/dashboard/agency/social/tiktok/callback", to: "dashboard/tiktok_connections#callback", as: :callback_dashboard_tiktok_connection
  get "/dashboard/agency/social", to: "dashboard/social_connections#index", as: :dashboard_social_connections
  post "/dashboard/agency/social", to: "dashboard/social_connections#create"
  post "/dashboard/agency/social/publish", to: "dashboard/social_connections#publish", as: :publish_dashboard_social_connection
  get "/dashboard/agency/reports", to: "dashboard/agency_reports#index", as: :dashboard_agency_reports
  post "/dashboard/marketing/campaigns/:id/schedule", to: "dashboard/marketing_campaigns#schedule", as: :schedule_dashboard_marketing_campaign
  get "/dashboard/business", to: "dashboard/business_hub#index", as: :dashboard_business_hub
  post "/dashboard/commerce/shop_page", to: "dashboard/commerce_products#create_shop_page", as: :dashboard_commerce_shop_page
  resources :dashboard_commerce_products, path: "/dashboard/commerce/products", controller: "dashboard/commerce_products", except: %i[show]
  post "/commerce/stripe/webhook", to: "commerce_stripe_webhooks#create", as: :commerce_stripe_webhook
  post "/dashboard/commerce/orders/:order_id/refund", to: "dashboard/commerce_refunds#create", as: :dashboard_commerce_refund
  get "/dashboard/commerce/industry/preview", to: "dashboard/commerce_products#preview_industry", as: :preview_dashboard_commerce_industry
  post "/dashboard/commerce/industry", to: "dashboard/commerce_products#install_industry", as: :dashboard_commerce_industry
  post "/dashboard/commerce/orders/:order_id/fulfill", to: "dashboard/commerce_fulfillments#create", as: :dashboard_commerce_fulfill
  post "/dashboard/commerce/products/:product_id/variants", to: "dashboard/commerce_variants#create", as: :dashboard_commerce_variants
  delete "/dashboard/commerce/products/:product_id/variants/:id", to: "dashboard/commerce_variants#destroy", as: :dashboard_commerce_variant
  get "/dashboard/commerce/payouts", to: "dashboard/commerce_payouts#index", as: :dashboard_commerce_payouts
  post "/dashboard/commerce/payouts/:order_id", to: "dashboard/commerce_payouts#create", as: :dashboard_commerce_payout
  post "/dashboard/network/cron_jobs", to: "dashboard/network#create_cron_job", as: :dashboard_network_cron_jobs
  patch "/dashboard/network/cron_jobs", to: "dashboard/network#update_cron_job"
  post "/dashboard/network/cron_jobs/run", to: "dashboard/network#run_cron_job", as: :dashboard_network_run_cron_job
  post "/dashboard/network/cron_jobs/toggle", to: "dashboard/network#toggle_cron_job", as: :dashboard_network_toggle_cron_job
  delete "/dashboard/network/cron_jobs", to: "dashboard/network#delete_cron_job"
  post "/dashboard/network/devices/:id/rotate_token", to: "dashboard/network#rotate_device_token", as: :dashboard_network_rotate_device_token
  post "/dashboard/network/devices", to: "dashboard/network#create_device", as: :dashboard_network_devices
  patch "/dashboard/network/devices/:id", to: "dashboard/network#update_device", as: :dashboard_network_device
  post "/dashboard/network/nodes/:id/verify", to: "dashboard/network#verify_node", as: :dashboard_network_verify_node
  post "/dashboard/network/dns/verify", to: "dashboard/network#verify_dns", as: :dashboard_network_verify_dns
  post "/dashboard/network/provisioning/:id/retry", to: "dashboard/network#retry_provisioning", as: :dashboard_network_retry_provisioning
  post "/dashboard/commerce/orders/:order_id/retry_provisioning", to: "dashboard/commerce_orders#retry_provisioning", as: :dashboard_commerce_retry_provisioning
  get "/commerce/shop", to: "commerce#index", as: :commerce_shop
  post "/commerce/shipping/quotes", to: "commerce_shipping_quotes#create", as: :commerce_shipping_quotes
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
  get "/employee/software-library", to: "employee/software_library#index", as: :employee_software_library
  get "/dashboard/nevaeh", to: "dashboard/nevaeh_os#index", as: :dashboard_nevaeh_os
  get "/dashboard/nevaeh/guide", to: "dashboard/nevaeh_os#guide", as: :dashboard_nevaeh_guide
  get "/dashboard/nevaeh/state", to: "dashboard/nevaeh_os#state"
  get "/dashboard/nevaeh/files/*filename", to: "dashboard/nevaeh_os#download", format: false
  post "/dashboard/nevaeh/files", to: "dashboard/nevaeh_os#upload"
  post "/dashboard/nevaeh/ask", to: "dashboard/nevaeh_os#ask"
  get "/dashboard/nevaeh/actions/:id", to: "dashboard/nevaeh_os#action"
  patch "/dashboard/nevaeh/consent", to: "dashboard/nevaeh_os#consent"
  post "/dashboard/nevaeh/memories", to: "dashboard/nevaeh_os#remember"
  delete "/dashboard/nevaeh/memories/:id", to: "dashboard/nevaeh_os#forget"

  get "/employee/nevaeh/help/:topic", to: "employee/nevaeh_help#show", as: :employee_nevaeh_help
  get "/employee/nevaeh/factory", to: "employee/nevaeh_factory#index", as: :employee_nevaeh_factory
  post "/employee/nevaeh/factory/constructions", to: "employee/nevaeh_factory#save_construction", as: :employee_nevaeh_factory_constructions
  patch "/employee/nevaeh/factory/constructions/:id", to: "employee/nevaeh_factory#save_construction", as: :employee_nevaeh_factory_construction
  post "/employee/nevaeh/factory/constructions/:id/build", to: "employee/nevaeh_factory#build", as: :employee_nevaeh_factory_build_construction
  post "/employee/nevaeh/factory/constructions/:id/pause", to: "employee/nevaeh_factory#pause", as: :employee_nevaeh_factory_pause_construction
  post "/employee/nevaeh/factory/releases/:id/activate", to: "employee/nevaeh_factory#activate", as: :employee_nevaeh_factory_activate_release
  post "/employee/nevaeh/factory/releases/:id/worker", to: "employee/nevaeh_factory#create_worker", as: :employee_nevaeh_factory_release_worker
  get "/employee/nevaeh/factory/releases/:id/artifacts", to: "employee/nevaeh_factory#artifacts", as: :employee_nevaeh_factory_release_artifacts
  post "/employee/nevaeh/factory/datasets", to: "employee/nevaeh_factory#save_dataset", as: :employee_nevaeh_factory_datasets
  patch "/employee/nevaeh/factory/datasets/:id", to: "employee/nevaeh_factory#save_dataset", as: :employee_nevaeh_factory_dataset
  post "/employee/nevaeh/factory/datasets/generate", to: "employee/nevaeh_factory#generate_dataset", as: :employee_nevaeh_factory_generate_dataset
  post "/employee/nevaeh/factory/datasets/:id/approve", to: "employee/nevaeh_factory#approve_dataset", as: :employee_nevaeh_factory_approve_dataset
  post "/employee/nevaeh/factory/models", to: "employee/nevaeh_factory#save_language_model", as: :employee_nevaeh_factory_language_models
  patch "/employee/nevaeh/factory/models/:id", to: "employee/nevaeh_factory#save_language_model", as: :employee_nevaeh_factory_language_model
  post "/employee/nevaeh/factory/models/:id/train", to: "employee/nevaeh_factory#train", as: :employee_nevaeh_factory_train_model
  post "/employee/nevaeh/factory/training/:id/cancel", to: "employee/nevaeh_factory#cancel_training", as: :employee_nevaeh_factory_cancel_training
  post "/employee/nevaeh/factory/checkpoints/:id/activate", to: "employee/nevaeh_factory#activate_checkpoint", as: :employee_nevaeh_factory_activate_checkpoint
  post "/employee/nevaeh/factory/conversations", to: "employee/nevaeh_factory#conversation", as: :employee_nevaeh_factory_conversations
  post "/employee/nevaeh/factory/conversations/:id/reply", to: "employee/nevaeh_factory#reply", as: :employee_nevaeh_factory_reply

  get "/employee/nevaeh/control-center", to: "employee/nevaeh_control_center#index", as: :employee_nevaeh_control_center
  post "/employee/nevaeh/workers", to: "employee/nevaeh_control_center#save_workflow", as: :employee_nevaeh_workers
  patch "/employee/nevaeh/workers/:id", to: "employee/nevaeh_control_center#save_workflow", as: :employee_nevaeh_worker
  post "/employee/nevaeh/workers/:id/run", to: "employee/nevaeh_control_center#run", as: :run_employee_nevaeh_worker
  post "/employee/nevaeh/writing-profiles", to: "employee/nevaeh_control_center#save_profile", as: :employee_nevaeh_writing_profiles
  patch "/employee/nevaeh/writing-profiles/:id", to: "employee/nevaeh_control_center#save_profile", as: :employee_nevaeh_writing_profile
  post "/employee/nevaeh/models", to: "employee/nevaeh_control_center#save_model", as: :employee_nevaeh_inference_models
  patch "/employee/nevaeh/models/:id", to: "employee/nevaeh_control_center#save_model", as: :employee_nevaeh_inference_model
  post "/employee/nevaeh/models/:id/infer", to: "employee/nevaeh_control_center#infer", as: :infer_employee_nevaeh_inference_model
  post "/employee/nevaeh/write", to: "employee/nevaeh_control_center#generate", as: :employee_nevaeh_write
  post "/employee/nevaeh/sample-context", to: "employee/nevaeh_control_center#sample_context", as: :employee_nevaeh_sample_context
  patch "/dashboard/nevaeh/navigation", to: "dashboard/nevaeh_navigation#update", as: :dashboard_nevaeh_navigation

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
get "/", to: redirect("/site/home", status: 302),constraints: { host: /(?:www\.)?lightekmcg\.com/ }
get "/", to: "gatekeeper/hosted_sites#show", constraints: ->(request) { Gatekeeper::Hosting::SiteRouting.match?(request.host) }
get "/site/:slug", to: "gatekeeper/hosted_sites#show", constraints: ->(request) { Gatekeeper::Hosting::SiteRouting.match?(request.host) }
get "/:slug", to: "gatekeeper/hosted_sites#show", constraints: ->(request) { Gatekeeper::Hosting::SiteRouting.page_match?(request) }
get "/__lightek/site-health", to: "gatekeeper/hosted_sites#health"
root to: redirect("/site/home", status: 302)

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
  post "callbacks/fleet_release", to: "fleet_releases#create", as: :fleet_release_callback
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

get "/__lightek/release", to: "gatekeeper/fleet_health#show", as: :gatekeeper_fleet_health

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
      member { patch :reply; patch :resolve; post :execute_nevaeh; post :resume_nevaeh; get :edit_nevaeh; post :revise_nevaeh }
    end
  root "dashboard#index"
  resources :clients,   only: %i[index show]
  resources :projects,  only: %i[index show edit update]
  resources :timesheets, only: %i[index create]
end

# ── Gatekeeper — Lightek client contract ──────────────────────────────────────
# Gatekeeper is the public experience/API contract for Roku and future clients.
post "gatekeeper/device", to: "gatekeeper#device_api", as: :gatekeeper_device
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

post "/gatekeeper/application-images", to: "gatekeeper/application_images#create", as: :gatekeeper_application_images
get "/dashboard/customers", to: "dashboard/customers#index", as: :dashboard_customers
get "/dashboard/customers/history", to: "dashboard/customers#history", as: :history_dashboard_customers
get "/dashboard/shipping", to: "dashboard/shipping#index", as: :dashboard_shipping
post "/dashboard/shipping/profile", to: "dashboard/shipping#profile", as: :dashboard_shipping_profile
post "/dashboard/shipping/quotes", to: "dashboard/shipping#quote", as: :dashboard_shipping_quotes
post "/dashboard/shipping/carrier", to: "dashboard/shipping#configure_carrier", as: :dashboard_shipping_carrier
post "/dashboard/shipping/:key/purchase", to: "dashboard/shipping#purchase", as: :purchase_dashboard_shipping
post "/dashboard/shipping/:key/refresh", to: "dashboard/shipping#refresh", as: :refresh_dashboard_shipping
post "/dashboard/shipping/:key/cancel", to: "dashboard/shipping#cancel", as: :cancel_dashboard_shipping
get "/dashboard/shipping/:key/label/:index", to: "dashboard/shipping#label", as: :label_dashboard_shipping
post "/api/reservations/federation/commerce/checkouts", to: "api/commerce_network#checkout"
get "/api/reservations/federation/commerce/orders/:key", to: "api/commerce_network#receipt"
post "/api/reservations/federation/commerce/orders/:key/fulfill", to: "api/commerce_network#fulfill"
post "/api/reservations/federation/commerce/orders/:key/refund", to: "api/commerce_network#refund"
post "/api/reservations/federation/commerce/orders/:key/payout", to: "api/commerce_network#payout"
post "/api/reservations/federation/commerce/orders/:key/cancel-subscription", to: "api/commerce_network#cancel_subscription"
post "/api/reservations/federation/commerce/connect", to: "api/commerce_network#connect"
post "/api/reservations/federation/commerce/summary", to: "api/commerce_network#summary"
post "/api/reservations/federation/shipping/quotes", to: "api/shipping_broker#quotes"
post "/api/reservations/federation/shipping/quotes/:key/purchase", to: "api/shipping_broker#purchase"
get "/api/reservations/federation/shipping/quotes/:key/status", to: "api/shipping_broker#status"
get "/api/reservations/federation/shipping/quotes/:key/labels/:index", to: "api/shipping_broker#label"
post "/api/reservations/federation/shipping/quotes/:key/cancel", to: "api/shipping_broker#cancel"
get "/dashboard/commerce", to: "dashboard/commerce#index", as: :dashboard_commerce
post "/dashboard/commerce/subscriptions/:id/cancel", to: "dashboard/commerce#cancel_subscription", as: :cancel_subscription_dashboard_commerce
resources :dashboard_agencies, path: "/dashboard/agencies", controller: "dashboard/agencies", only: %i[index create update] do
  member do
    post :create_client
    patch :update_terms
  end
end
resources :dashboard_hosting_packages, path: "/dashboard/hosting/packages", controller: "dashboard/hosting_packages", only: %i[index create update]
post "/dashboard/hosting/purchase", to: "dashboard/hosting_purchases#create", as: :dashboard_hosting_purchase
resources :dashboard_application_launches, path: "/dashboard/applications/install", controller: "dashboard/application_launches", only: %i[new create] do
  collection do
    post :create_template
    post :build_image
    post :setup_builds
  end
  member do
    post :retry
    patch :disable_template
  end
end
post "/dashboard/vault/repair-access", to: "dashboard/vault#repair_access", as: :repair_access_dashboard_vault
get "/dashboard/infrastructure/catalog", to: "dashboard/infrastructure_catalog#index", as: :dashboard_infrastructure_catalog
resources :dashboard_servers, path: "/dashboard/servers", controller: "dashboard/server_instances", only: %i[index show destroy] do
  collection { get :hosting }
  member do
    post :create_application
    post :retry_application
  end
end
resources :dashboard_fleet_updates, path: "/dashboard/infrastructure/updates", controller: "dashboard/fleet_updates", only: %i[index show create] do
  collection do
    post :sync
    post :release
    patch :installation
    post :register_installation
  end
  member { post :control }
end
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
  post "/dashboard/website/designs/convert", to: "dashboard/website_designs#convert_html", as: :convert_dashboard_website_designs
  post "/dashboard/website/designs/upload", to: "dashboard/website_designs#upload_html", as: :upload_dashboard_website_designs
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
  post "/accounts/:account_id/receiving-check", action: :check_receiving, as: :check_receiving_dashboard_mail
  post "/accounts/:account_id/token", action: :token, as: :dashboard_mail_token
  get "/accounts/:account_id/compose", action: :compose, as: :compose_dashboard_mail
  post "/accounts/:account_id/bulk", action: :bulk_messages, as: :bulk_dashboard_mail
  post "/accounts/:account_id/undo", action: :undo_messages, as: :undo_dashboard_mail
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
get "/api/lightek-mail/routes", to: "api/lightek_mail#routes"
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



  get "/api/lightek/ott/catalog", to: "api/lightek_pwa#ott_catalog"
  get "/api/lightek/pwa/live/:post_id/index.m3u8", to: "api/lightek_pwa#live_playlist"
  get "/api/lightek/pwa/live/:post_id/segments/:name", to: "api/lightek_pwa#live_segment", constraints: { name: /segment-\d+\.ts/ }, format: false
  get "/api/lightek/pwa/assets/:id/:flavor", to: "api/lightek_pwa#asset_file"
  get "/api/lightek/pwa/posts/:post_id/media/:attachment_id", to: "api/lightek_pwa#media"
  get "/api/lightek/pwa/communities/:slug/cover", to: "api/lightek_pwa#cover"
  get "/api/lightek/pwa", to: "api/lightek_pwa#show"
  get "/api/lightek/pwa/communities/:slug/spatial-assets", to: "api/lightek_pwa#spatial_hub"
  post "/api/lightek/pwa/studio/hub/import", to: "api/lightek_pwa#spatial_hub_import"
  get "/api/lightek/pwa/posts/:post_id/spatial", to: "api/lightek_pwa#spatial_manifest"
  get "/api/lightek/pwa/posts/:post_id/spatial/assets/:asset_id", to: "api/lightek_pwa#spatial_asset"
  post "/api/lightek/pwa/posts/:post_id/spatial/fork", to: "api/lightek_pwa#spatial_fork"
  post "/api/lightek/pwa/studio/generation", to: "api/lightek_pwa#spatial_generation"
  post "/api/lightek/pwa/studio/spatial", to: "api/lightek_pwa#spatial_session"
  post "/internal/studio/spatial/commit", to: "api/studio/spatial_commits#create"
  post "/api/lightek/pwa/uploads", to: "api/lightek_pwa#upload"
  get "/api/nevaeh/executions/:id", to: "api/nevaeh#execution"

  get "/api/nevaeh/bootstrap",
      to: "api/nevaeh#bootstrap"


  post "/api/nevaeh/payment_quote",
       to: "api/nevaeh/payment_quotes#create"


  post "/api/nevaeh/execute",
       to: "api/nevaeh#execute"

end
