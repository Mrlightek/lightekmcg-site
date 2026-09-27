class ComputeProvider < ApplicationRecord
  ADAPTER_TYPES = %w[builtin declarative custom].freeze
  STATUSES = %w[draft validating active disabled].freeze
  HEALTH_STATUSES = %w[unknown healthy degraded failed].freeze

  validates :name, :slug, :adapter_type, :status, :health_status, presence: true
  validates :slug, uniqueness: true
  validates :adapter_type, inclusion: { in: ADAPTER_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :health_status, inclusion: { in: HEALTH_STATUSES }

  scope :active, -> { where(status: "active") }

  def adapter(requested_by: "system", operation_id: nil)
    Gatekeeper::Compute::Registry.build(self, requested_by:, operation_id:)
  end

  def capability?(name)
    capabilities.to_h[name.to_s] == true
  end

  def credential_configured?
    credential_secret_slug.present?
  end

  def mark_health!(status:, metadata: {})
    update!(
      health_status: status,
      last_healthcheck_at: Time.current,
      metadata: self.metadata.to_h.merge("last_healthcheck" => metadata)
    )
  end
end
