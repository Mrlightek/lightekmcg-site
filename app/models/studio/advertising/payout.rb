# frozen_string_literal: true

module Studio
  module Advertising
    class Payout < ApplicationRecord
      self.table_name = "studio_ad_payouts"

      belongs_to :payment, class_name: "Studio::Advertising::Payment"
      belongs_to :recipient, class_name: "::User"
      attr_readonly :payment_id, :recipient_id, :role, :amount_cents

      validates :role, inclusion: { in: %w[station producer network] }
      validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
    end
  end
end
