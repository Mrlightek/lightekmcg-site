module LightekVault
  class Secret < ApplicationRecord
    self.table_name = "lightek_vault_secrets"

    TYPES = %w[credential api_key password certificate signing_key ssh_key wireguard_key dkim_key webhook_secret database_credential].freeze
    STATUSES = %w[active disabled expired].freeze

    has_many :audit_events, class_name: "LightekVault::AuditEvent", foreign_key: :secret_id, dependent: :destroy

    validates :name, :slug, :secret_type, :environment, :status, presence: true
    validates :slug, uniqueness: true
    validates :secret_type, inclusion: { in: TYPES }
    validates :status, inclusion: { in: STATUSES }

    scope :active, -> { where(status: "active", disabled_at: nil) }
    scope :expiring_soon, -> { active.where(expires_at: Time.current..30.days.from_now) }

    def disabled? = status == "disabled" || disabled_at.present?
    def expired? = status == "expired" || (expires_at.present? && expires_at <= Time.current)
    def usable? = !disabled? && !expired?
    def display_provider = provider.presence || "internal"
  end
end
