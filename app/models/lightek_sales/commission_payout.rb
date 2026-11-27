# frozen_string_literal: true

module LightekSales
  class CommissionPayout < ApplicationRecord
    self.table_name = 'lightek_sales_commission_payouts'

    belongs_to :referral
    belongs_to :order, class_name: 'LightekCommerce::Order'
    belongs_to :owner, class_name: 'User'
    belongs_to :released_by, class_name: 'User', optional: true

    attr_readonly :referral_id, :order_id, :owner_id, :amount_cents, :sender_ref, :recipient_ref, :live

    def provider_metadata
      {'commission_payout_id' => id.to_s, 'referral_id' => referral_id.to_s,
       'commerce_order_id' => order_id.to_s, 'site_id' => order.site_id.to_s}
    end
  end
end
