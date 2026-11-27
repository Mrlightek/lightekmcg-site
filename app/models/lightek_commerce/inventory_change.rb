# frozen_string_literal: true

require 'securerandom'

module LightekCommerce
  class InventoryChange < ApplicationRecord
    self.table_name = 'lightek_commerce_inventory_changes'

    scope :for_site, ->(site) { where(site_id: site.id) }

    def self.record!(product:, actor:, before_quantity:, after_quantity:, source:, variant: nil, batch_key: SecureRandom.uuid)
      create!(site_id: product.site_id, product_id: product.id, variant_id: variant&.id,
        actor_id: actor.id, actor_name: actor.full_name.presence || "Account ##{actor.id}",
        product_name: product.name, variant_name: variant&.name, batch_key: batch_key,
        before_quantity: before_quantity, after_quantity: after_quantity, source: source)
    end

    def source_label = source == 'product_editor' ? 'Product editor' : 'CSV upload'

    def readonly? = persisted?
  end
end
