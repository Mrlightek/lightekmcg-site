# frozen_string_literal: true
module DymondCatalog
  # Merchandising projection only. Bank remains the authority for price and payment.
  class MarketplaceListing < ActiveRecord::Base
    self.table_name = "dymond_catalog_marketplace_listings"
    CATEGORIES = {"cloud" => "Cloud & Websites", "entertainment" => "Entertainment",
      "finance" => "Dymond Bank", "creators" => "Creator Tools"}.freeze
    def self.category_labels
      LightekMarketplace::ProductGroup.available.pluck(:key, :name).to_h
    end
    belongs_to :offer, class_name: "DymondBank::Offer"
    validates :offer_id, uniqueness: true
    validates :title, presence: true, length: {maximum: 160}
    validates :summary, length: {maximum: 1200}
    validates :category, inclusion: {in: ->(_) { category_labels.keys }}
    validates :position, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validate :published_offer_is_active
    scope :storefront, -> { joins(:offer).where(published: true)
      .where(dymond_bank_offers: {active: true}).order(:position, :id) }

    private
    def published_offer_is_active
      errors.add(:offer, "must be active before publishing") if published? && !offer&.active?
    end
  end
end
