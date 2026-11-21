# frozen_string_literal: true

module Studio
  module Advertising
    class ProviderStatement < ApplicationRecord
      self.table_name = "studio_ad_provider_statements"
      belongs_to :source, class_name: "Studio::Advertising::DemandSource"
      belongs_to :reconciled_by, class_name: "User", optional: true
      validates :reference, presence: true, length: { maximum: 180 }, uniqueness: { scope: :source_id }
      validates :impressions, :reported_cents, numericality: { only_integer: true, in: 0..1_000_000_000_000 }
      validates :received_cents, numericality: { only_integer: true, in: 0..1_000_000_000_000 }, allow_nil: true
      validates :deposit_reference, length: { maximum: 180 }
      validate { errors.add(:ends_on, "must be on or after the start date") unless starts_on && ends_on && ends_on >= starts_on }
      attr_readonly :source_id, :reference, :starts_on, :ends_on, :impressions, :reported_cents

      def reconcile!(received:, deposit:, operator:)
        with_lock do
          raise ArgumentError, "A receipt has already been reconciled for this statement." if reconciled_at?
          raise ArgumentError, "Enter the bank deposit or adjustment reference." if deposit.blank?

          update!(received_cents: Integer(received.to_s, 10), deposit_reference: deposit,
            reconciled_at: Time.current, reconciled_by: operator)
        end
      end

      def variance_cents = received_cents && received_cents - reported_cents
    end
  end
end
