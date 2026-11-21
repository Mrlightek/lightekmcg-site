# frozen_string_literal: true

module Studio
  module Broadcasting
    class BroadcastContractSignature < ApplicationRecord
      self.table_name = "studio_broadcast_contract_signatures"
      belongs_to :version, class_name: "Studio::Broadcasting::BroadcastContractVersion"
      belongs_to :signer, class_name: "::User"
      attr_readonly :version_id, :signer_id, :party, :signer_name, :document_digest, :signed_at
      validates :party, inclusion: { in: %w[issuer counterparty] }
      validates :signer_name, presence: true, length: { maximum: 160 }
    end
  end
end
