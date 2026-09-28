class StudioOperation < ApplicationRecord
  STATUSES = %w[awaiting_planning awaiting_approval pending running completed failed cancelled].freeze

  belongs_to :studio_project
  belongs_to :production, optional: true
  belongs_to :studio_scene, optional: true
  has_many :artifacts, dependent: :destroy

  validates :operation_type, :provider, :capability, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :json_payloads_must_be_objects

  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[awaiting_planning awaiting_approval pending running]) }

  def terminal? = status.in?(%w[completed failed cancelled])
  def executable? = status.in?(%w[pending awaiting_approval])

  private

  def json_payloads_must_be_objects
    %i[intent manifest cost_quote metadata].each do |attribute|
      errors.add(attribute, "must be a JSON object") unless public_send(attribute).is_a?(Hash)
    end
  end
end
