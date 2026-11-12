module LightekCommerce
  class NetworkSale < ApplicationRecord
    self.table_name = "lightek_commerce_network_sales"
    belongs_to :peer, class_name: "LightekReservations::Peer"
    belongs_to :order, class_name: "LightekCommerce::Order"
    belongs_to :source_shipping_quote, class_name: "LightekShipping::Quote", optional: true
    before_validation { self.public_key ||= SecureRandom.uuid }
  end
end
