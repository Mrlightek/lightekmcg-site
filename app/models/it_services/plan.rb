module ItServices
  class Plan < ApplicationRecord
    self.table_name = "it_service_plans"

    belongs_to :product, class_name: "LightekCommerce::Product"
    belongs_to :resource, class_name: "LightekReservations::Resource"
    has_many :memberships, dependent: :restrict_with_error

    attr_readonly :product_id, :resource_id
    validate :matching_service_offer

    def available?
      product.published? && resource.published? && compatible?
    end

    def compatible?
      product&.product_type == "service" && product.billing_interval.in?(%w[month year]) &&
        product.price_cents.positive? && !product.communications_kind &&
        resource&.kind == "service" && resource.product_id.nil? &&
        product.site_id == resource.site_id && !LightekReservations::Federation::Client.config(product.site)
    end

    private

    def matching_service_offer
      return if compatible?

      errors.add(:base, "Choose a recurring service product and an included service reservation from the same local website.")
    end
  end
end
