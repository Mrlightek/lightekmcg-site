# frozen_string_literal: true

module Studio
  module Broadcasting
    class BroadcastContractEvidence < ApplicationRecord
      self.table_name = "studio_broadcast_contract_evidence"
      KINDS = { "delivery" => "Delivered units", "reviewed_payment" => "Reviewed payment (USD)" }.freeze
      belongs_to :version, class_name: "Studio::Broadcasting::BroadcastContractVersion"
      belongs_to :recorded_by, class_name: "::User"
      attr_readonly :version_id, :recorded_by_id, :kind, :quantity, :reference, :occurred_on
      validates :kind, inclusion: { in: %w[delivery reviewed_payment] }
      validates :quantity, numericality: { only_integer: true, in: 1..99_999_999_999 }
      validates :reference, presence: true, length: { maximum: 200 }
      validates :occurred_on, presence: true
      validate :validate_evidence

      private

      def validate_evidence
        return unless version

        errors.add(:version, "must be signed by both parties") unless version.executed?
        if version.contract.kind == "sponsor" || (kind == "delivery" && version.terms_snapshot["delivery_mode"] == "booked_spots")
          errors.add(:kind, "is verified from booked spots")
        end
        if self.class.where(version_id: version.evidence_version_ids, kind: kind, reference: reference).exists?
          errors.add(:reference, "was already recorded for this agreement term")
        end
        return unless occurred_on

        allowed = kind == "delivery" ? version.starts_on..version.ends_on : version.starts_on..Date.current
        errors.add(:occurred_on, "must be within the applicable dates") unless occurred_on <= Date.current && allowed.cover?(occurred_on)
      end
    end
  end
end
