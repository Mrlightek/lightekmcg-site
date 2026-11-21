# frozen_string_literal: true

module Studio
  module Advertising
    class Campaign < ApplicationRecord
      self.table_name = "studio_ad_campaigns"
      BREAKS = %w[pre_roll mid_roll pre_end_roll].freeze
      SHARE_FIELDS = %i[network_bps producer_bps platform_bps].freeze

      belongs_to :network, class_name: "Studio::Advertising::Network"
      belongs_to :asset, class_name: "::StudioAsset"
      has_many :placements, class_name: "Studio::Advertising::Placement", dependent: :restrict_with_error
      scope :offered, -> { where(open_for_booking: true) }

      def self.for_station(site_id)
        own = Network.where(site_id: site_id, imported: false).select(:id)
        joined = Membership.where(station_site_id: site_id).select(:network_id)
        offered.where(network_id: own).or(offered.where(network_id: joined))
      end

      attr_readonly :network_id, :asset_id, :blob_id, :name, :seconds, :rate_cents, *SHARE_FIELDS
      validates :name, presence: true, length: { maximum: 100 }
      validates :seconds, numericality: { only_integer: true, in: 2..120 }
      validates :rate_cents, numericality: { only_integer: true, in: 1..1_000_000 }
      validates(*SHARE_FIELDS, numericality: { only_integer: true, in: 0..10_000 })
      validate :validate_terms
      validate :validate_creative, on: :create

      def creative_available?
        asset && asset.site_id == network&.site_id && asset.kind == "video" && asset.status == "ready" &&
          asset.proxy.attached? && asset.proxy.blob.id == blob_id && asset.metadata["duration"].to_f.floor >= seconds.to_i
      end

      def split
        amounts = SHARE_FIELDS.to_h do |field|
          [field.to_s.sub(/_bps\z/, "_cents").to_sym, rate_cents * public_send(field) / 10_000]
        end
        amounts.merge(station_cents: rate_cents - amounts.values.sum)
      end

      private

      def validate_terms
        errors.add(:base, "The shares must leave a percentage for the station.") if SHARE_FIELDS.sum { |field| public_send(field).to_i } >= 10_000
        return if rate_cents.to_i < 1
        SHARE_FIELDS.each do |field|
          points = public_send(field).to_i
          errors.add(field, "must earn at least one cent per airing") if points.positive? && rate_cents * points < 10_000
        end
      end

      def validate_creative
        errors.add(:asset, "must be a ready video from this ad network’s site and fit the slot") unless creative_available?
      end
    end
  end
end
