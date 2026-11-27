# frozen_string_literal: true

module LightekSales
  class Partner < ApplicationRecord
    self.table_name = 'lightek_sales_partners'

    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :product, class_name: 'LightekCommerce::Product'
    has_many :referrals, class_name: 'LightekSales::Referral', dependent: :restrict_with_error

    scope :active, -> { where(revoked_at: nil) }

    before_validation(on: :create) { self.referral_code ||= SecureRandom.hex(20) }
    validate do
      errors.add(:product, 'must belong to this website') if product && product.site_id != site_id
    end
    validates :name, :agreement_reference, presence: true, length: {maximum: 160}
    validates :commission_cents, numericality: {
      only_integer: true, greater_than: 0, less_than_or_equal_to: 100_000_000
    }
  end
end
