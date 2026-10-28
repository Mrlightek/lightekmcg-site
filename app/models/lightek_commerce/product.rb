# frozen_string_literal: true
module LightekCommerce
  # Merchant-owned goods are separate from Lightek's Marketplace service offers.
  # Every installation retains its own database and sites; ownership is scoped per site.
  class Product < ApplicationRecord
    self.table_name = "lightek_commerce_products"
    belongs_to :site, class_name: "DymondSite::Site"
    validates :name, presence: true, length: {maximum: 160}
    validates :slug, presence: true, length: {maximum: 180}, format: {with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/}
    validates :slug, uniqueness: {scope: :site_id}
    validates :currency, inclusion: {in: %w[usd]}
    validates :price_cents, :inventory_quantity, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    scope :visible, -> { where(published: true).order(:position, :id) }
  end
end
