# frozen_string_literal: true

module Studio
  module Advertising
    class Payment < ApplicationRecord
      self.table_name = "studio_ad_payments"

      belongs_to :placement, class_name: "Studio::Advertising::Placement"
      has_many :payouts, class_name: "Studio::Advertising::Payout", dependent: :restrict_with_error
      has_secure_token :public_key, length: 32
      attr_readonly :placement_id, :public_key, :amount_cents

      validates :state, inclusion: { in: %w[unfunded authorized captured void held] }

      def self.reserve!(placement)
        payment = create!(placement: placement, amount_cents: placement.campaign.rate_cents)
        { "station" => placement.station_site.tenant, "producer" => placement.producer,
          "network" => placement.campaign.network.site.tenant }.each do |role, user|
          amount = placement.public_send("#{role}_cents")
          next if amount.zero?

          raise ArgumentError, "Each paid share needs an account owner." unless user.is_a?(::User)
          payment.payouts.create!(recipient: user, role: role, amount_cents: amount)
        end
        payment
      end

      def ready_at?(ends_at)
        state == "authorized" && authorized_until && authorized_until > ends_at + 10.minutes
      end

      def can_book_payment?
        placement.payable_airing? && placement.booked_start.between?(60.minutes.from_now, 5.days.from_now)
      end
    end
  end
end
