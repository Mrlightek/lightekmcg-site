# frozen_string_literal: true

module LightekSales
  class Partner < ApplicationRecord
    self.table_name = 'lightek_sales_partners'

    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :product, class_name: 'LightekCommerce::Product'
    belongs_to :payout_user, class_name: 'User', optional: true
    belongs_to :payout_invited_by, class_name: 'User', optional: true
    validates :payout_email, format: {with: URI::MailTo::EMAIL_REGEXP}, length: {maximum: 254}, allow_nil: true

    generates_token_for :payout_setup, expires_in: 2.days do
      [payout_email, payout_invited_by_id, payout_user_id, revoked_at&.to_i]
    end

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
