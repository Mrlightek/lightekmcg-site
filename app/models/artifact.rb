class Artifact < ApplicationRecord
  KINDS = %w[blend glb preview manifest log video audio image poster thumbnail subtitle package].freeze

  belongs_to :creation_job, optional: true
  belongs_to :studio_operation, optional: true
  has_many :studio_publications, dependent: :destroy
  has_one_attached :file

  validates :kind, inclusion: { in: KINDS }
  validates :filename, presence: true
  validate :must_have_owner

  private

  def must_have_owner
    return if creation_job_id.present? || studio_operation_id.present?

    errors.add(:base, "Artifact must belong to a creation job or studio operation")
  end
end
