require "uri"

module LightekShipping
  class Quote < ApplicationRecord
    self.table_name = "lightek_shipping_quotes"
    belongs_to :site, class_name: "DymondSite::Site"
    belongs_to :purchase_order, class_name: "LightekCommerce::Order", optional: true
    has_one :shipment, dependent: :restrict_with_error
    before_validation { self.public_key ||= SecureRandom.uuid }
    validates :public_key, uniqueness: true, presence: true
    validates :provider, inclusion: {in: ->(_) { LightekShipping::Account::PROVIDERS }}
    validates :currency, inclusion: {in: ["usd"]}
    validates :platform_price_cents, numericality: {only_integer: true, greater_than: 0}
    validates :customer_price_cents, numericality: {only_integer: true, greater_than_or_equal_to: :platform_price_cents}
    def carrier_tracking_url(number)
      self.class.carrier_tracking_url(provider, number)
    end

    def self.carrier_tracking_url(provider, number)
      tracking = number.to_s
      if provider == 'ups' && tracking.match?(/\A[A-Z0-9]{8,35}\z/)
        "https://www.ups.com/track?#{URI.encode_www_form(tracknum: tracking)}"
      elsif provider == 'fedex' && tracking.match?(/\A\d{8,35}\z/)
        "https://www.fedex.com/fedextrack/?#{URI.encode_www_form(trknbr: tracking)}"
      end
    end

    def public_attributes
      {key: public_key, provider: provider, service_code: service_code, service_name: service_name,
        price_cents: platform_price_cents, currency: currency, sandbox: sandbox?, expires_at: expires_at.iso8601}
    end
  end
end
