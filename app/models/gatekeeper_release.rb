class GatekeeperRelease < ApplicationRecord
  IMAGE = /\Aghcr\.io\/[a-z0-9][a-z0-9._\/-]*@sha256:[a-f0-9]{64}\z/
  has_many :gatekeeper_rollouts, dependent: :restrict_with_error
  before_validation { self.image = nil if new_record? && image.blank? }
  attr_readonly :version, :source_sha, :image, :channel, :backward_compatible, :notes, :created_by, :adapter, :component, :repository
  validates :version, :created_by, presence: true
  validates :version, uniqueness: true, length: {maximum: 100}
  validates :source_sha, format: {with: /\A[a-f0-9]{40}\z/}
  validates :image, format: {with: IMAGE}, if: -> { adapter == "docker_compose" }
  validates :adapter, inclusion: {in: Gatekeeper::Fleet::Adapters::NAMES}
  validates :component, format: {with: /\A[a-z][a-z0-9_-]{0,79}\z/}
  validate do
    errors.add(:repository, "must be a credential-free Git repository URL") unless Gatekeeper::Fleet::Adapters.repository?(repository)
    errors.add(:image, "is only supported for Docker installations") if adapter != "docker_compose" && image.present?
  end
  validates :channel, inclusion: {in: %w[stable beta]}
end
