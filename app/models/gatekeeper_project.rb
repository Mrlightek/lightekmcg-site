class GatekeeperProject < ApplicationRecord
  STATUSES = %w[unknown provisioning healthy degraded deploying failed].freeze

  belongs_to :gatekeeper_node
  has_many :gatekeeper_operations, dependent: :nullify

  validates :name, :repository, :domain, :app_root, :ruby_version, presence: true
  validates :name, :domain, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  def sidekiq_service
    sidekiq_service_name.presence || "#{name}-sidekiq"
  end

  def health_url
    metadata["health_url"].presence || "https://#{domain}/up"
  end
end
