class GatekeeperRelease < ApplicationRecord
  IMAGE = /\Aghcr\.io\/[a-z0-9][a-z0-9._\/-]*@sha256:[a-f0-9]{64}\z/
  has_many :gatekeeper_rollouts, dependent: :restrict_with_error
  attr_readonly :version, :source_sha, :image, :channel, :backward_compatible, :notes, :created_by
  validates :version, :created_by, presence: true
  validates :version, uniqueness: true, length: {maximum: 100}
  validates :source_sha, format: {with: /\A[a-f0-9]{40}\z/}
  validates :image, format: {with: IMAGE}
  validates :channel, inclusion: {in: %w[stable beta]}
end
