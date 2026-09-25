class GatekeeperOperation < ApplicationRecord
  STATUSES = %w[queued running succeeded failed].freeze

  belongs_to :gatekeeper_node
  belongs_to :gatekeeper_project, optional: true

  has_one :support_ticket,
          -> { where(related_type: "GatekeeperOperation") },
          class_name: "Marlon::Ticket",
          foreign_key: :related_id,
          dependent: :nullify,
          inverse_of: false

  validates :capability, :requested_by, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :failed, -> { where(status: "failed") }

  def ticketed?
    support_ticket.present?
  end
end
