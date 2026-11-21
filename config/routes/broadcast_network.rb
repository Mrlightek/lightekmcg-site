get "/gatekeeper/linear/:channel_id/:name", to: "linear_channel_streams#show", format: false,
  constraints: { channel_id: /[0-9]+/, name: /index\.m3u8|out-[0-9]+\.ts/ }
get "/watch/tv/measurement/:channel_id", to: "broadcast_tv#measurement", constraints: { channel_id: /[0-9]+/ }
get "/watch/tv", to: "broadcast_tv#show", as: :broadcast_tv
get "/dashboard/live/network", to: "dashboard/broadcast_network#show", as: :dashboard_broadcast_network
post "/dashboard/live/network/channels/:channel_id", to: "dashboard/broadcast_network#station_carriage", as: :dashboard_station_carriage
post "/dashboard/live/network/lineup/:channel_id", to: "dashboard/broadcast_network#hub_carriage", as: :dashboard_hub_carriage
post "/dashboard/live/network/licenses", to: "dashboard/broadcast_network#offer_license", as: :dashboard_program_licenses
post "/dashboard/live/network/licenses/:license_id/accept", to: "dashboard/broadcast_network#accept_license", as: :dashboard_accept_program_license
post "/dashboard/live/network/licenses/:license_id/withdraw", to: "dashboard/broadcast_network#withdraw_license", as: :dashboard_withdraw_program_license
get "/dashboard/live/network/audience.csv", to: "dashboard/broadcast_network#audience_csv", as: :dashboard_broadcast_audience
get "/dashboard/live/network/measurement.json", to: "dashboard/broadcast_network#measurement_metadata", as: :dashboard_broadcast_measurement
post "/dashboard/live/network/portfolio", to: "dashboard/broadcast_network#install_portfolio", as: :dashboard_broadcast_portfolio
post "/api/reservations/federation/broadcast/channels/:key", to: "api/broadcast_carriage#save", constraints: { key: /[0-9a-f]{32}/ }
get "/gatekeeper/network/:key/:name", to: "affiliate_channel_streams#show", format: false,
  constraints: { key: /[0-9a-f]{32}/, name: /index\.m3u8|measurement\.json|(?:fallback-[0-9]+-)?out-[0-9]+\.ts/ }
get "/gatekeeper/affiliate-source/:key/:name", to: "affiliate_channel_streams#source", format: false,
  constraints: { key: /[0-9a-f]{32}/, name: /index\.m3u8|measurement\.json|out-[0-9]+\.ts/ }
post "/dashboard/live/network/hosted/:key", to: "dashboard/broadcast_network#hosted_carriage", as: :dashboard_hosted_carriage
get "/api/reservations/federation/broadcast/programs", to: "api/broadcast_programs#index"
put "/api/reservations/federation/broadcast/programs/:key/media", to: "api/broadcast_programs#upload", constraints: { key: /[0-9a-f]{32}/ }
get "/api/reservations/federation/broadcast/programs/:key/media", to: "api/broadcast_programs#download", constraints: { key: /[0-9a-f]{32}/ }
post "/api/reservations/federation/broadcast/programs/:key/accept", to: "api/broadcast_programs#accept", constraints: { key: /[0-9a-f]{32}/ }
get "/api/reservations/federation/broadcast/programs/:key/status", to: "api/broadcast_programs#status", constraints: { key: /[0-9a-f]{32}/ }
post "/api/reservations/federation/broadcast/programs/:key/withdraw", to: "api/broadcast_programs#withdraw", constraints: { key: /[0-9a-f]{32}/ }
post "/dashboard/live/network/licenses/hosted", to: "dashboard/broadcast_network#offer_hosted_license", as: :dashboard_hosted_program_licenses
post "/dashboard/live/network/licenses/hosted/:key/accept", to: "dashboard/broadcast_network#accept_hosted_license", as: :dashboard_accept_hosted_program_license
post "/dashboard/live/network/licenses/hosted/:key/withdraw", to: "dashboard/broadcast_network#withdraw_hosted_license", as: :dashboard_withdraw_hosted_program_license
get "/dashboard/live/network/operations", to: "dashboard/broadcast_operations#show", as: :dashboard_broadcast_operations
post "/dashboard/live/network/operations/agreements", to: "dashboard/broadcast_operations#offer_agreement", as: :dashboard_broadcast_agreements
post "/dashboard/live/network/operations/agreements/:id/accept", to: "dashboard/broadcast_operations#accept_agreement", as: :dashboard_accept_broadcast_agreement
post "/dashboard/live/network/operations/packages", to: "dashboard/broadcast_operations#create_package", as: :dashboard_broadcast_packages
get "/dashboard/live/network/operations/packages/:id.csv", to: "dashboard/broadcast_operations#package_report", as: :dashboard_broadcast_package_report
post "/dashboard/live/network/operations/plans", to: "dashboard/broadcast_operations#save_plan", as: :dashboard_broadcast_plans
patch "/dashboard/live/network/operations/plans/:id", to: "dashboard/broadcast_operations#save_plan", as: :dashboard_broadcast_plan
get "/broadcast-ads/package/:key", to: "broadcast_sponsor_packages#show", as: :broadcast_sponsor_package,
  constraints: { key: /[a-zA-Z0-9]{32}/ }
post "/dashboard/live/network/operations/agreements/hosted/:id/accept", to: "dashboard/broadcast_operations#accept_hosted_agreement", as: :dashboard_accept_hosted_broadcast_agreement
get "/api/reservations/federation/broadcast/agreements", to: "api/broadcast_carriage#agreements"
post "/api/reservations/federation/broadcast/agreements/:id/accept", to: "api/broadcast_carriage#accept_agreement"
post "/dashboard/live/network/licenses/:license_id/sublicense", to: "dashboard/broadcast_network#sublicense", as: :dashboard_sublicense_program
post "/api/reservations/federation/broadcast/programs/:key/sublicense", to: "api/broadcast_programs#sublicense", constraints: { key: /[0-9a-f]{32}/ }
post "/dashboard/live/network/licenses/:license_id/clips", to: "dashboard/broadcast_network#create_clip", as: :dashboard_create_program_clip
post "/dashboard/live/network/clips/:id/withdraw", to: "dashboard/broadcast_network#withdraw_clip", as: :dashboard_withdraw_program_clip
get "/watch/clips/:key", to: "broadcast_program_clips#show", as: :broadcast_program_clip, constraints: { key: /[a-zA-Z0-9]{32}/ }
get "/watch/clips/:key/video", to: "broadcast_program_clips#video", as: :broadcast_program_clip_video, constraints: { key: /[a-zA-Z0-9]{32}/ }
