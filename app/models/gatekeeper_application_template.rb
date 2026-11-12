class GatekeeperApplicationTemplate < ApplicationRecord
  validates :name, presence: true, length: {maximum: 120}
  validates :kind, inclusion: {in: %w[native_rails docker]}
  validates :container_port, numericality: {only_integer: true, greater_than: 0, less_than: 65536}
  validates :image, format: {with: /\A[a-z0-9][a-z0-9.:-]*(?:\/[a-z0-9][a-z0-9._-]*)+@sha256:[a-f0-9]{64}\z/}, if: -> { kind == "docker" && build_status == "ready" }
  validates :credential_slug, format: {with: /\A[a-z0-9][a-z0-9_-]*\z/}, allow_blank: true
  validates :build_status, inclusion: {in: %w[queued ready failed]}
  validate do
    errors.add(:rails_worker, "requires the Rails PostgreSQL/Redis stack") if kind == "docker" && rails_worker? && !rails_database?
  end
  def self.ensure_native!
    find_or_create_by!(kind: "native_rails", name: "LightekMCG · Rails with Docker dependencies") do |template|
      template.container_port = 3000
      template.enabled = true
      template.build_status = "ready"
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(kind: "native_rails", name: "LightekMCG · Rails with Docker dependencies")
  end

  scope :available, -> { where(enabled: true, build_status: "ready").order(:name) }
end
