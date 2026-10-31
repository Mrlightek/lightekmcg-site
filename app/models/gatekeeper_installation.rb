class GatekeeperInstallation < ApplicationRecord
  belongs_to :gatekeeper_node
  belongs_to :gatekeeper_project, optional: true
  belongs_to :account, class_name: "User", optional: true
  belongs_to :pinned_release, class_name: "GatekeeperRelease", optional: true
  has_many :gatekeeper_update_targets, dependent: :restrict_with_error
  validates :domain, presence: true, uniqueness: {scope: [:gatekeeper_node_id, :component]},
    format: {with: /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\z/}, length: {maximum: 253}
  validates :channel, inclusion: {in: %w[stable beta]}
  validates :adapter, inclusion: {in: Gatekeeper::Fleet::Adapters::NAMES}
  validates :component, format: {with: /\A[a-z][a-z0-9_-]{0,79}\z/}
  validate :valid_profile

  def valid_profile
    errors.add(:repository, "must be a credential-free Git repository URL") unless Gatekeeper::Fleet::Adapters.repository?(repository)
    if pinned_release && (pinned_release.adapter != adapter || pinned_release.component != component ||
        Gatekeeper::Fleet::Adapters.repository_key(pinned_release.repository) != Gatekeeper::Fleet::Adapters.repository_key(repository))
      errors.add(:pinned_release, "must match the installation's adapter, component and repository")
    end
    Gatekeeper::Fleet::Adapters.validate!(adapter, deployment_config) unless deployment_config.blank?
  rescue ArgumentError => error
    errors.add(:deployment_config, error.message)
  end

  def accepts_release?(release)
    eligible? && channel == release.channel && adapter == release.adapter && component == release.component &&
      Gatekeeper::Fleet::Adapters.repository_key(repository) == Gatekeeper::Fleet::Adapters.repository_key(release.repository) &&
      (pinned_release_id.nil? || pinned_release_id == release.id)
  end

  def configured?
    Gatekeeper::Fleet::Adapters.validate!(adapter, deployment_config)
  rescue ArgumentError
    false
  end

  def eligible?
    node = gatekeeper_node
    central_app = component == "lightek_app" && (node.metadata.to_h["role"] == "production" || node.metadata.to_h["local_node"])
    enabled? && configured? && !node.local? && !%w[decommissioned deleting delete_failed].include?(node.status) && !central_app
  end
end
