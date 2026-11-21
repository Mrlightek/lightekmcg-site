# frozen_string_literal: true

require "digest"

module Studio
  module Broadcasting
    class BroadcastContractVersion < ApplicationRecord
      self.table_name = "studio_broadcast_contract_versions"
      SIGNING_INTENT = "I agree to this version and intend to sign it electronically.".freeze

      belongs_to :contract, class_name: "Studio::Broadcasting::BroadcastContract"
      belongs_to :offered_by, class_name: "::User"
      has_many :signatures, class_name: "Studio::Broadcasting::BroadcastContractSignature", foreign_key: :version_id,
        dependent: :restrict_with_exception
      has_many :evidence, class_name: "Studio::Broadcasting::BroadcastContractEvidence", foreign_key: :version_id,
        dependent: :restrict_with_exception

      attr_readonly :contract_id, :offered_by_id, :number, :starts_on, :ends_on, :terms_snapshot, :document_digest
      validates :starts_on, :ends_on, :document_digest, presence: true
      validates :number, numericality: { only_integer: true, greater_than: 0 }
      validate :validate_terms

      def self.fingerprint(number, start, finish, snapshot)
        Digest::SHA256.hexdigest(JSON.generate([number, start.iso8601, finish.iso8601, snapshot.sort.to_h]))
      end

      def executed? = signatures.size == 2

      def evidence_version_ids
        ids = [id]
        cursor = self
        while (previous_id = cursor.terms_snapshot["amends_version_id"])
          cursor = contract.versions.find(previous_id)
          break if ids.include?(cursor.id)

          ids << cursor.id
        end
        ids
      end

      def sign!(actor:, party:, name:, digest:)
        contract.with_lock do
          reload
          raise ArgumentError, "Open the current offer before signing." unless digest == document_digest && !withdrawn_at?
          raise ArgumentError, "This offer has expired." if ends_on < Date.current

          other_party = signatures.where.not(party: party).first
          raise ArgumentError, "The two parties must sign under different accounts." if other_party&.signer_id == actor.id

          signatures.create_or_find_by!(party: party) do |signature|
            signature.assign_attributes(signer: actor, signer_name: name.to_s.strip, signed_at: Time.current, document_digest: document_digest)
          end
        end
      end

      def withdraw!
        contract.with_lock do
          reload
          raise ArgumentError, "An executed agreement is retained. Offer an amendment instead." if executed?

          update!(withdrawn_at: Time.current) unless withdrawn_at?
        end
      end

      def executed_copy
        raise ActiveRecord::RecordNotFound unless executed?

        parts = [terms_snapshot.fetch("title"), "Version #{number}", "Issuer — #{terms_snapshot.fetch('issuer')}",
          "Counterparty — #{terms_snapshot.fetch('counterparty')}", "Term — #{starts_on.iso8601} through #{ends_on.iso8601}",
          "Market — #{terms_snapshot['market']}", "Promised deliveries — #{terms_snapshot.fetch('delivery_target')}",
          "Delivery evidence — #{terms_snapshot.fetch('delivery_mode').humanize}",
          "Agreed amount — USD #{format('%.2f', terms_snapshot.fetch('amount_cents') / 100.0)}",
          ("Fixed fee due — #{terms_snapshot.fetch('due_on')}" unless contract.kind == "sponsor"),
          "Referenced ad payments — #{terms_snapshot.fetch('payment_ids').join(', ')}", terms_snapshot.fetch("terms")]
        terms_snapshot.fetch("carriage_terms").each { |key, value| parts << "#{CarriageAgreement::TERMS.fetch(key)}\n#{value}" }
        terms_snapshot.fetch("booked_spots").each do |spot|
          parts << ["Payment #{spot.fetch('payment_id')}", spot.fetch("campaign"), spot.fetch("station"), spot["channel"],
            spot.fetch("scheduled_at"), "USD #{format('%.2f', spot.fetch('amount_cents') / 100.0)}"].compact.join(" · ")
        end
        parts.compact!
        parts << "SHA-256 — #{document_digest}"
        signatures.order(:signed_at, :id).each do |signature|
          parts << "#{signature.party.humanize} signature — #{signature.signer_name} (account #{signature.signer_id}) at #{signature.signed_at.utc.iso8601}"
        end
        (parts << SIGNING_INTENT).join("\n\n")
      end

      private

      def validate_terms
        terms = terms_snapshot
        errors.add(:ends_on, "must follow the start date") if starts_on && ends_on && ends_on < starts_on
        errors.add(:terms_snapshot, "requires terms and a counterparty") if terms["terms"].blank? || terms["terms"].length > 20_000 || terms["counterparty"].blank?
        errors.add(:terms_snapshot, "has an invalid delivery mode") unless terms["delivery_mode"].in?(%w[reviewed booked_spots])
        errors.add(:terms_snapshot, "has an invalid market") if terms["market"].to_s.length > 120
        errors.add(:terms_snapshot, "has an invalid delivery target or amount") unless terms["delivery_target"].in?(0..100_000) && terms["amount_cents"].in?(0..99_999_999_999)
      end
    end
  end
end
