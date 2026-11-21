get "/gatekeeper/linear/:channel_id/:name", to: "linear_channel_streams#show", format: false,
  constraints: { channel_id: /[0-9]+/, name: /index\.m3u8|out-[0-9]+\.ts/ }
get "/watch/tv", to: "broadcast_tv#show", as: :broadcast_tv
get "/dashboard/live/network", to: "dashboard/broadcast_network#show", as: :dashboard_broadcast_network
post "/dashboard/live/network/channels/:channel_id", to: "dashboard/broadcast_network#station_carriage", as: :dashboard_station_carriage
post "/dashboard/live/network/lineup/:channel_id", to: "dashboard/broadcast_network#hub_carriage", as: :dashboard_hub_carriage
post "/dashboard/live/network/licenses", to: "dashboard/broadcast_network#offer_license", as: :dashboard_program_licenses
post "/dashboard/live/network/licenses/:license_id/accept", to: "dashboard/broadcast_network#accept_license", as: :dashboard_accept_program_license
post "/dashboard/live/network/licenses/:license_id/withdraw", to: "dashboard/broadcast_network#withdraw_license", as: :dashboard_withdraw_program_license
get "/dashboard/live/network/audience.csv", to: "dashboard/broadcast_network#audience_csv", as: :dashboard_broadcast_audience
get "/dashboard/live/network/measurement.json", to: "dashboard/broadcast_network#measurement_metadata", as: :dashboard_broadcast_measurement
