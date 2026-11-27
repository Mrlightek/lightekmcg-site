# frozen_string_literal: true

module LightekCommerce
  class InventoryChange < ApplicationRecord
    self.table_name = 'lightek_commerce_inventory_changes'

    scope :for_site, ->(site) { where(site_id: site.id) }

    def readonly? = persisted?
  end
end
