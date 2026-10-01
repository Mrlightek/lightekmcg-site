class StudioPublication < ApplicationRecord
  PLATFORMS = %w[
    tiktok
    instagram
    facebook
    lightek_social
    lightek_streaming
    octavia
  ].freeze
  STATUSES = %w[draft scheduled publishing published failed cancelled].freeze

  belongs_to :studio_project
  belongs_to :production, optional: true
  belongs_to :artifact

  validates :platform, inclusion: { in: PLATFORMS }
  validates :status, inclusion: { in: STATUSES }
  validate :metadata_must_be_an_object

  scope :due, -> { where(status: "scheduled").where("scheduled_at <= ?", Time.current) }

  private

  def metadata_must_be_an_object
    errors.add(:metadata, "must be a JSON object") unless metadata.is_a?(Hash)
  end
end
