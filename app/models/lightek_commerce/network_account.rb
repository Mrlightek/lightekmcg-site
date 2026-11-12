module LightekCommerce
  class NetworkAccount < ApplicationRecord
    self.table_name = "lightek_commerce_network_accounts"
    belongs_to :peer, class_name: "LightekReservations::Peer"
    belongs_to :user
    belongs_to :site, class_name: "DymondSite::Site"
  end
end
