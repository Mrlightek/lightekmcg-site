module LightekShipping
  class Quote < ApplicationRecord
    self.table_name = "lightek_shipping_quotes"
    belongs_to :site, class_name: "DymondSite::Site"
    belongs_to :purchase_order, class_name: "LightekCommerce::Order", optional: true
    has_one :shipment, dependent: :restrict_with_error
    before_validation { self.public_key ||= SecureRandom.uuid }
    validates :public_key, uniqueness: true, presence: true
    validates :currency, inclusion: {in: ["usd"]}
    validates :platform_price_cents, numericality: {only_integer: true, greater_than: 0}
    validates :customer_price_cents, numericality: {only_integer: true, greater_than_or_equal_to: :platform_price_cents}
    def public_attributes
      {key: public_key, service_code: service_code, service_name: service_name,
        price_cents: platform_price_cents, currency: currency, sandbox: sandbox?, expires_at: expires_at.iso8601}
    end
  end
end
