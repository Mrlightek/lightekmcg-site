post "/api/reservations/federation/ads/sales", to: "api/broadcast_ad_exchange#sales"
get "/api/reservations/federation/ads/catalog", to: "api/broadcast_ad_exchange#catalog"
get "/api/reservations/federation/ads/offers/:key", to: "api/broadcast_ad_exchange#offer"
post "/api/reservations/federation/ads/offers/:key", to: "api/broadcast_ad_exchange#save_offer"
post "/api/reservations/federation/ads/placements/:key", to: "api/broadcast_ad_exchange#placement"
post "/dashboard/live/advertising/exchange/:key", to: "dashboard/broadcast_advertising#import_offer", as: :dashboard_broadcast_ad_import
