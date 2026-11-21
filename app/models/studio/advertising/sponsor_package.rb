# frozen_string_literal: true

module Studio
  module Advertising
    class SponsorPackage < ApplicationRecord
      self.table_name = "studio_sponsor_packages"
      belongs_to :site, class_name: "DymondSite::Site"
      has_many :spots, class_name: "Studio::Advertising::SponsorPackageSpot", foreign_key: :package_id,
        dependent: :restrict_with_error
      has_many :payments, through: :spots
      has_secure_token :public_key, length: 32
      validates :name, presence: true, length: { maximum: 120 }

      def self.sellable_payments(site)
        Payment.joins(placement: { campaign: :network })
          .where(studio_ad_networks: { site_id: site.id, imported: false })
          .where.not(id: SponsorPackageSpot.select(:payment_id))
      end

      def self.book!(site:, name:, payment_ids:)
        ids = payment_ids.reject(&:blank?).uniq
        raise ArgumentError, "Choose between 1 and 50 booked spots." unless ids.size.between?(1, 50)

        transaction do
          payments = sellable_payments(site).where(id: ids, state: "unfunded").order(:id).lock("FOR UPDATE OF studio_ad_payments").to_a
          unless payments.size == ids.size && payments.all? { |payment| payment.placement.payable_airing? }
            raise ArgumentError, "All spots must be unassigned and booked on a published channel in this site's ad networks."
          end

          package = create!(site: site, name: name)
          payments.each { |payment| package.spots.create!(payment: payment) }
          package
        end
      rescue ActiveRecord::RecordNotUnique
        raise ArgumentError, "A spot was just added to another package. Choose the available spots and try again."
      end

      def report_payments
        payments.includes(:payouts, placement: [:station_site, :campaign, { airing: :channel }]).order(:id)
      end
    end
  end
end
