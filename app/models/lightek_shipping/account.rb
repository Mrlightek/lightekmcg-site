module LightekShipping
  class Account < ApplicationRecord
    self.table_name = "lightek_shipping_accounts"
    PROVIDERS = %w[fedex ups].freeze
    UPS_MARKUP_CENTS = 200

    validates :provider, inclusion: {in: PROVIDERS}, uniqueness: true
    validates :credential_slug, presence: true
    validates :markup_bps, :fixed_markup_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :minimum_margin_cents, numericality: {only_integer: true, greater_than: 0}
    validate { errors.add(:production_approved, "Carrier production approval is required") if enabled? && !sandbox? && !production_approved? }
    def carrier_class
      case provider
      when 'fedex' then Fedex
      when 'ups' then Ups
      else raise ArgumentError, 'Unsupported carrier'
      end
    end

    def retail_cents(cost)
      raise ArgumentError, "Carrier quote must be positive" unless cost.is_a?(Integer) && cost.positive?
      return cost + UPS_MARKUP_CENTS if provider == 'ups'

      floor = [((cost * (10_000 + markup_bps) + 9999) / 10_000) + fixed_markup_cents, cost + minimum_margin_cents].max
      LightekCommerce::MerchantPayouts.minimum_charge_cents(floor)
    end
  end
end
