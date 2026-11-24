# frozen_string_literal: true

class ItRemoteSupportTransfer < ApplicationRecord
  belongs_to :it_remote_support_session
  belongs_to :sender, class_name: "User"

  scope :pending, -> { where(state: %w[scanning awaiting_acceptance accepted]) }

  def recipient?(user)
    sender_id != user.id && [it_remote_support_session.customer_id, it_remote_support_session.technician_id].include?(user.id)
  end
end
