# frozen_string_literal: true
module LightekMarketplace
  class ProductGroup < ActiveRecord::Base
    self.table_name = "lightek_marketplace_product_groups"
    attr_readonly :key
    scope :available, -> { where(active: true).order(:position, :id) }
    before_validation :derive_key, on: :create
    validates :key, presence: true, uniqueness: true, format: {with: /\A[a-z][a-z0-9_]*\z/}
    validates :name, presence: true, uniqueness: {case_sensitive: false}, length: {maximum: 100}
    validates :description, length: {maximum: 500}
    validates :position, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validate :keep_used_groups_available
    private
    def derive_key
      if key.blank?
        derived = name.to_s.parameterize(separator: "_")
        self.key = derived.match?(/\A[a-z]/) ? derived : "group_#{derived}"
      end
    end
    def keep_used_groups_available
      if !active? && DymondCatalog::MarketplaceListing.where(category: key).exists?
        errors.add(:active, "cannot be turned off while products use this group. Move those products first.")
      end
    end
  end
end
