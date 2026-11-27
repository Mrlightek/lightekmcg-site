# frozen_string_literal: true

require 'securerandom'

module LightekCommerce
  class InventoryChange < ApplicationRecord
    self.table_name = 'lightek_commerce_inventory_changes'

    scope :for_site, ->(site) { where(site_id: site.id) }

    def self.record!(product:, before_quantity:, after_quantity:, source:, actor: nil, order: nil, variant: nil, batch_key: SecureRandom.uuid)
      create!(site_id: product.site_id, product_id: product.id, variant_id: variant&.id,
        actor_id: actor&.id, actor_name: actor ? (actor.full_name.presence || "Account ##{actor.id}") : 'System',
        order_id: order&.id,
        product_name: product.name, variant_name: variant&.name, batch_key: batch_key,
        before_quantity: before_quantity, after_quantity: after_quantity, source: source)
    end

    SOURCE_LABELS = {'csv_import' => 'CSV upload', 'product_editor' => 'Product editor',
      'checkout_reserved' => 'Checkout reservation', 'checkout_released' => 'Stock released'}.freeze

    def source_label = SOURCE_LABELS.fetch(source)

    def readonly? = persisted?
  end
end
