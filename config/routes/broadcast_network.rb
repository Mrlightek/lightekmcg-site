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

get "/dashboard/live/contracts", to: "dashboard/broadcast_contracts#index", as: :dashboard_broadcast_contracts
post "/dashboard/live/contracts", to: "dashboard/broadcast_contracts#create"
post "/dashboard/live/contracts/network-report/delivery-rates", to: "dashboard/broadcast_contracts#delivery_rates", as: :dashboard_broadcast_delivery_rates
post "/dashboard/live/contracts/network-report/support", to: "dashboard/broadcast_contracts#delivery_support", as: :dashboard_broadcast_delivery_support
get "/dashboard/live/contracts/network-report", to: "dashboard/broadcast_contracts#network", as: :dashboard_broadcast_network_report
get "/dashboard/live/contracts/archives/:id", to: "dashboard/broadcast_contracts#archive", as: :dashboard_broadcast_report_archive
get "/dashboard/live/contracts/carriage/:id/report", to: "dashboard/broadcast_contracts#carriage_report", as: :dashboard_carriage_agreement_report
get "/dashboard/live/contracts/hosted/:id", to: "dashboard/broadcast_contracts#hosted", as: :dashboard_hosted_broadcast_contract
post "/dashboard/live/contracts/hosted/:id/sign", to: "dashboard/broadcast_contracts#sign_hosted", as: :dashboard_sign_hosted_broadcast_contract
get "/dashboard/live/contracts/hosted/:id/versions/:version_id/:document", to: "dashboard/broadcast_contracts#hosted_document",
  as: :dashboard_hosted_broadcast_document, constraints: { document: /report|copy/ }
get "/dashboard/live/contracts/performance", to: "dashboard/broadcast_contracts#portfolio_report", as: :dashboard_broadcast_contract_performance
get "/dashboard/live/contracts/:id", to: "dashboard/broadcast_contracts#show", as: :dashboard_broadcast_contract
post "/dashboard/live/contracts/:id/versions", to: "dashboard/broadcast_contracts#revise", as: :dashboard_revise_broadcast_contract
post "/dashboard/live/contracts/:id/versions/:version_id/sign", to: "dashboard/broadcast_contracts#sign", as: :dashboard_sign_broadcast_contract
post "/dashboard/live/contracts/:id/versions/:version_id/withdraw", to: "dashboard/broadcast_contracts#withdraw", as: :dashboard_withdraw_broadcast_contract
post "/dashboard/live/contracts/:id/versions/:version_id/evidence", to: "dashboard/broadcast_contracts#record_evidence", as: :dashboard_record_broadcast_contract_evidence
get "/dashboard/live/contracts/:id/versions/:version_id/report", to: "dashboard/broadcast_contracts#report", as: :dashboard_broadcast_contract_report
get "/dashboard/live/contracts/:id/versions/:version_id/copy", to: "dashboard/broadcast_contracts#executed_copy", as: :dashboard_broadcast_contract_copy
get "/api/reservations/federation/broadcast/agreements/:id/contract", to: "api/broadcast_carriage#contract"
post "/api/reservations/federation/broadcast/agreements/:id/contract/sign", to: "api/broadcast_carriage#sign_contract"
get "/api/reservations/federation/broadcast/agreements/:id/contract/versions/:version_id/report", to: "api/broadcast_carriage#contract_report"
get "/api/reservations/federation/broadcast/agreements/:id/contract/versions/:version_id/copy", to: "api/broadcast_carriage#contract_copy"
get "/dashboard/live/contracts/licenses/:id/report", to: "dashboard/broadcast_contracts#license_report", as: :dashboard_program_license_performance
get "/dashboard/live/contracts/hosted/:id/report", to: "dashboard/broadcast_contracts#hosted_document",
  as: :dashboard_hosted_carriage_performance, defaults: { document: "report" }
get "/api/reservations/federation/broadcast/agreements/:id/contract/report", to: "api/broadcast_carriage#legacy_contract_report"

post "/dashboard/live/network/licenses/:license_id/handoffs", to: "dashboard/program_distribution_handoffs#create", as: :dashboard_program_distribution_handoffs
get "/dashboard/live/network/handoffs/:id", to: "dashboard/program_distribution_handoffs#show", as: :dashboard_program_distribution_package
post "/dashboard/live/network/handoffs/:id/review", to: "dashboard/program_distribution_handoffs#review", as: :dashboard_program_distribution_review
post "/dashboard/live/network/handoffs/:id/submission", to: "dashboard/program_distribution_handoffs#record_submission", as: :dashboard_program_distribution_receipt
get "/dashboard/live/network/handoffs/:id/manifest", to: "dashboard/program_distribution_handoffs#manifest", as: :dashboard_program_distribution_manifest
get "/dashboard/live/network/handoffs/:id/media", to: "dashboard/program_distribution_handoffs#media", as: :dashboard_program_distribution_media
post "/dashboard/live/network/licenses/:license_id/screening", to: "dashboard/broadcast_network#publish_web_screening", as: :dashboard_publish_program_screening
delete "/dashboard/live/network/licenses/:license_id/screening", to: "dashboard/broadcast_network#remove_web_screening", as: :dashboard_remove_program_screening
get "/watch/programs/:key", to: "broadcast_program_screenings#show", as: :broadcast_program_screening, constraints: { key: /[A-Za-z0-9]{32}/ }
get "/watch/programs/:key/video", to: "broadcast_program_screenings#video", as: :broadcast_program_screening_video, constraints: { key: /[A-Za-z0-9]{32}/ }
post "/dashboard/live/network/owned-programs", to: "dashboard/broadcast_network#register_owned_program", as: :dashboard_register_owned_program

get "/api/broadcast/advertising/wrapper-impression", to: "broadcast_ad_decisions#impression", as: :broadcast_wrapper_impression
get "/api/broadcast/advertising/decision/:decision_key", to: "broadcast_ad_decisions#show", as: :broadcast_ad_decision,
  format: false, constraints: { decision_key: /[A-Za-z0-9]{48}/ }
post "/watch/tv/fewer-commercials", to: "broadcast_viewing_offers#checkout", as: :broadcast_viewing_offer
post "/dashboard/live/advertising/demand", to: "dashboard/broadcast_advertising#create_demand", as: :dashboard_broadcast_ad_demand
patch "/dashboard/live/advertising/demand/:id", to: "dashboard/broadcast_advertising#update_demand", as: :dashboard_broadcast_ad_demand_source
post "/dashboard/live/advertising/stream", to: "dashboard/broadcast_advertising#save_stream_profile", as: :dashboard_broadcast_ad_stream_profile
delete "/dashboard/live/advertising/stream/:id", to: "dashboard/broadcast_advertising#remove_stream_profile", as: :dashboard_remove_broadcast_ad_stream_profile
post "/dashboard/live/advertising/statement", to: "dashboard/broadcast_advertising#record_provider_statement", as: :dashboard_broadcast_ad_statement
post "/dashboard/live/advertising/statement/:id/reconcile", to: "dashboard/broadcast_advertising#reconcile_provider_statement", as: :dashboard_reconcile_broadcast_ad_statement
post "/dashboard/live/advertising/viewing-offer", to: "dashboard/broadcast_advertising#save_viewing_offer", as: :dashboard_broadcast_ad_viewing_offer
post "/watch/tv/link-roku", to: "broadcast_viewing_links#create", as: :broadcast_viewing_link
post "/api/broadcast/viewing-links/redeem", to: "broadcast_viewing_links#redeem"
