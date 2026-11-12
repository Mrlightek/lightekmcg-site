# frozen_string_literal: true
module LightekCommerce
  # Merchant-owned goods are separate from Lightek's Marketplace service offers.
  # Every installation retains its own database and sites; ownership is scoped per site.
  class Product < ApplicationRecord
    self.table_name = "lightek_commerce_products"
    has_one :hosting_package, dependent: :restrict_with_error
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
    validate :instance_plan_required
    def instance_plan_required
      errors.add(:subscription_plan_id, "required for a Lightek instance") if product_type == "lightek_instance" && subscription_plan_id.blank?
    end
    validates :shipping_weight_lb, numericality: {greater_than: 0, less_than_or_equal_to: 150}, allow_nil: true
    validates :shipping_length_in, :shipping_width_in, :shipping_height_in, numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: 108}, allow_nil: true
    validates :billing_interval, inclusion: {in: %w[one_time month year]}
    validate do
      errors.add(:price_cents, "must be positive for subscriptions") if billing_interval != "one_time" && price_cents.to_i <= 0
      errors.add(:billing_interval, "subscriptions must be services or managed installations") if billing_interval != "one_time" && !%w[service lightek_instance].include?(product_type)
      if persisted? && hosting_package && (billing_interval != "month" || product_type != "lightek_instance" || price_cents.to_i < hosting_package.monthly_cost_ceiling_cents + hosting_package.minimum_margin_cents)
        errors.add(:price_cents, "must preserve the hosting package's monthly retail margin")
      end
    end
    validates :product_type, inclusion: {in: %w[physical digital service lightek_instance]}
    validates :image_url, format: {with: /\Ahttps:\/\//}, allow_blank: true
    validates :short_description, length: {maximum: 300}
    validates :sku, uniqueness: {scope: :site_id}, allow_blank: true
    scope :visible, -> { where(published: true).order(:position, :id) }
  end
end
