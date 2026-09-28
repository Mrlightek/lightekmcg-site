class StudioLiveOperation < ApplicationRecord
  PLATFORMS = %w[tiktok instagram facebook lightek_social].freeze
  STATUSES = %w[draft scheduled connecting live ending ended failed cancelled].freeze

  belongs_to :studio_project
  belongs_to :production, optional: true

  validates :platform, inclusion: { in: PLATFORMS }
  validates :status, inclusion: { in: STATUSES }
  validate :policy_payloads_must_be_objects

  def live? = status == "live"

  private

  def policy_payloads_must_be_objects
    %i[response_policy moderation_policy metrics metadata].each do |attribute|
      errors.add(attribute, "must be a JSON object") unless public_send(attribute).is_a?(Hash)
    end
  end
end
