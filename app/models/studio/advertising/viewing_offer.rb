# frozen_string_literal: true

module Studio
  module Advertising
    class ViewingOffer < ApplicationRecord
      self.table_name = "studio_ad_viewing_offers"
      belongs_to :site, class_name: "DymondSite::Site"
      belongs_to :product, class_name: "LightekCommerce::Product"
      validate do
        unless product && product.site_id == site_id && product.product_type == "service" &&
            product.billing_interval.in?(%w[month year]) && product.published?
          errors.add(:product, "must be a published recurring service on this site")
        end
      end

      def self.active?(site, user)
        return false unless user

        offer = find_by(site: site)
        return false unless offer

        orders = LightekCommerce::Order.where(site: site, hosting_owner: user, purpose: "fewer_commercials", status: %w[paid fulfilled])
          .where.not(paid_at: nil).joins(:items).where(lightek_commerce_order_items: { product_id: offer.product_id })
        LightekCommerce::Subscription.where(order_id: orders.select(:id), status: "active")
          .where("current_period_end > ?", Time.current).exists?
      end
    end
  end
end
