# frozen_string_literal: true

module Studio
  module Broadcasting
    class BroadcastContract < ApplicationRecord
      self.table_name = "studio_broadcast_contracts"
      KINDS = %w[carriage sponsor producer].freeze

      belongs_to :site, class_name: "DymondSite::Site"
      belongs_to :counterparty, class_name: "::User", optional: true
      belongs_to :carriage_agreement, class_name: "Studio::Broadcasting::CarriageAgreement", optional: true
      belongs_to :sponsor_package, class_name: "Studio::Advertising::SponsorPackage", optional: true
      has_many :versions, class_name: "Studio::Broadcasting::BroadcastContractVersion", foreign_key: :contract_id,
        dependent: :restrict_with_exception

      attr_readonly :site_id, :counterparty_id, :carriage_agreement_id, :sponsor_package_id, :kind, :title
      validates :kind, inclusion: { in: KINDS }
      validates :title, presence: true, length: { maximum: 120 }
      validate :validate_parties

      def counterparty_site = carriage_agreement&.station_site

      def counterparty_name
        counterparty_site&.name || counterparty&.full_name.presence || counterparty&.email_address
      end

      def self.incoming(user)
        sites = Access.sites(user)
        local = CarriageAgreement.where(station_site_id: sites, hosted_carriage_id: nil)
        where(counterparty: user).or(where(carriage_agreement_id: local.select(:id)))
      end

      def offer!(actor:, starts_on:, ends_on:, terms:, delivery_target:, amount_cents:, market:, payment_ids: [], due_on: nil, delivery_mode: "reviewed")
        with_lock do
          latest = versions.order(number: :desc).first
          if latest && !latest.executed? && !latest.withdrawn_at?
            raise ArgumentError, "Withdraw the unsigned offer or finish signing it before issuing a revision."
          end

          prior = versions.includes(:signatures).order(number: :desc).find(&:executed?)
          renewal = prior && starts_on > prior.ends_on
          if prior && !renewal && (starts_on != prior.starts_on || ends_on != prior.ends_on)
            raise ArgumentError, "Use the existing dates for an amendment or start a renewal after the signed term ends."
          end

          recipient = (kind == "producer" ? counterparty : counterparty_site&.tenant)
          recipient_id = recipient.id if recipient.is_a?(User)
          payments = payment_rows(payment_ids, recipient_id: recipient_id).to_a
          if kind != "sponsor" && payments.size != payment_ids.size
            raise ArgumentError, "Choose payments for this counterparty from this site's ad networks."
          end

          amount_cents = payments.sum(&:amount_cents) if kind == "sponsor"
          if kind == "sponsor"
            unless payments.all? { |payment| payment.placement.booked_start&.utc&.to_date&.between?(starts_on, ends_on) }
              raise ArgumentError, "The sponsor term must include every spot booked in this package."
            end
            delivery_target = payments.size
            delivery_mode = "booked_spots"
          end
          if delivery_mode == "booked_spots" && payments.empty?
            raise ArgumentError, "Link booked payments to verify delivery from the playout records."
          end

          if kind != "sponsor" && payments.any? { |payment| !payment.placement.booked_start&.utc&.to_date&.between?(starts_on, ends_on) }
            raise ArgumentError, "Every referenced payment must be for a spot in the agreement window."
          end

          booked = payments.map do |payment|
            placement = payment.placement
            { "payment_id" => payment.id, "campaign" => placement.campaign.name, "station" => placement.station_site.name,
              "channel" => placement.airing&.channel&.name, "scheduled_at" => placement.booked_start&.utc&.iso8601,
              "amount_cents" => (kind == "sponsor" ? payment.amount_cents : payment.payouts.find { |row| row.role == payout_role }&.amount_cents) }
          end
          snapshot = { "kind" => kind, "title" => title, "issuer" => site.name, "counterparty" => counterparty_name,
            "market" => market, "terms" => terms, "delivery_target" => delivery_target, "amount_cents" => amount_cents,
            "payment_ids" => payments.map(&:id), "booked_spots" => booked,
            "delivery_mode" => delivery_mode, "payout_recipient_id" => recipient_id,
            "due_on" => (due_on || ends_on).iso8601,
            "amends_version_id" => (prior.id if prior && !renewal), "carriage_terms" => carriage_agreement&.terms.to_h.sort.to_h }
          fingerprint = BroadcastContractVersion.fingerprint(latest&.number.to_i + 1, starts_on, ends_on, snapshot)
          versions.create!(offered_by: actor, number: latest&.number.to_i + 1, starts_on: starts_on,
            ends_on: ends_on, terms_snapshot: snapshot, document_digest: fingerprint)
        end
      end

      def payout_role
        { "producer" => "producer", "carriage" => "station" }[kind]
      end

      def payment_rows(ids, recipient_id:)
        payment = Studio::Advertising::Payment
        return sponsor_package.report_payments if kind == "sponsor"

        return payment.none unless recipient_id && ids.any?

        own = payment.where(placement: managed_placements).where(id: ids)
        own.where(id: Studio::Advertising::Payout.where(role: payout_role, recipient_id: recipient_id).select(:payment_id))
          .includes(:payouts, placement: [:station_site, :campaign, { airing: :channel }]).order(:id)
      end

      private

      def managed_placements
        network = Studio::Advertising::Network.where(site_id: site_id, imported: false)
        campaign = Studio::Advertising::Campaign.where(network: network)
        placements = Studio::Advertising::Placement.where(campaign: campaign)
        return placements unless carriage_agreement

        if carriage_agreement.channel_id?
          placements.where(airing: Airing.where(channel_id: carriage_agreement.channel_id))
        else
          placements.where(peer_id: carriage_agreement.hosted_carriage.peer_id, station_site_id: carriage_agreement.station_site_id)
        end
      end

      def validate_parties
        valid = case kind
        when "carriage"
          carriage_agreement&.outlet_site_id == site_id && counterparty.nil? && sponsor_package.nil?
        when "sponsor"
          sponsor_package&.site_id == site_id && counterparty.present? && carriage_agreement.nil?
        when "producer"
          counterparty.present? && sponsor_package.nil? && carriage_agreement.nil?
        end
        errors.add(:base, "Choose a valid source and counterparty for this agreement.") unless valid
      end
    end
  end
end
