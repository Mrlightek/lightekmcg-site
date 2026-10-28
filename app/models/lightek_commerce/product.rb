# frozen_string_literal: true
module LightekCommerce
  # Merchant-owned goods are separate from Lightek's Marketplace service offers.
  # Every installation retains its own database and sites; ownership is scoped per site.
  class Product < ApplicationRecord
    self.table_name = "lightek_commerce_products"
    has_many :variants, class_name: "LightekCommerce::ProductVariant", dependent: :restrict_with_error
    has_many_attached :photos
    validate :photo_constraints
    def photo_constraints
      photos.each do |photo|
        errors.add(:photos, "must be JPEG, PNG or WebP") unless %w[image/jpeg image/png image/webp].include?(photo.blob.content_type)
        errors.add(:photos, "must be smaller than 10 MB") if photo.blob.byte_size > 10.megabytes
      end
      errors.add(:photos, "cannot exceed 8 images") if photos.size > 8
    end
    belongs_to :site, class_name: "DymondSite::Site"
    validates :name, presence: true, length: {maximum: 160}
    validates :slug, presence: true, length: {maximum: 180}, format: {with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/}
    validates :slug, uniqueness: {scope: :site_id}
    validates :currency, inclusion: {in: %w[usd]}
    validates :price_cents, :inventory_quantity, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :product_type, inclusion: {in: %w[physical digital]}
    validates :image_url, format: {with: /\Ahttps:\/\//}, allow_blank: true
    validates :short_description, length: {maximum: 300}
    validates :sku, uniqueness: {scope: :site_id}, allow_blank: true
    scope :visible, -> { where(published: true).order(:position, :id) }
  end
end
