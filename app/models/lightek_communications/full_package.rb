module LightekCommunications
  class FullPackage < ApplicationRecord
    self.table_name = "lightek_full_packages"

    belongs_to :order, class_name: "LightekCommerce::Order"
    belongs_to :buyer, class_name: "User"
  end
end
