# frozen_string_literal: true

class NevaehIntelligence < ApplicationRecord
  STATUSES = %w[draft published archived].freeze
  OPERATIONS = %w[create read update delete generate execute publish].freeze
  EXECUTION_MODES = %w[sync async].freeze

  belongs_to :nevaeh_capability

  validates :name, :intent_key, :operation, presence: true
  validates :intent_key, uniqueness: true, format: { with: /\A[a-z][a-z0-9_.]*\z/ }
  validates :status, inclusion: { in: STATUSES }
  validates :operation, inclusion: { in: OPERATIONS }
  validates :execution_mode, inclusion: { in: EXECUTION_MODES }
  validate :instructions_must_be_object

  scope :published, -> { where(status: 'published') }
  scope :available, -> { published.joins(:nevaeh_capability).where(nevaeh_capabilities: { enabled: true }) }

  def dispatch_action
    instructions.fetch('action', operation).to_s
  end

  private

  def instructions_must_be_object
    errors.add(:instructions, 'must be a JSON object') unless instructions.is_a?(Hash)
  end
end
