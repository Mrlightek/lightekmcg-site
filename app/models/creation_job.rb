class CreationJob < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :studio_scene
  has_many :artifacts, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :manifest, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  def pending? = status == "pending"
end

