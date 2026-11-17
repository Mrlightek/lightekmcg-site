module LightekPwa
  class SharedPool < ApplicationRecord
    self.table_name = 'lightek_pwa_shared_pools'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :operator, class_name: 'User'
    belongs_to :launch, class_name: 'GatekeeperApplicationLaunch', optional: true
    belongs_to :node, class_name: 'GatekeeperNode', optional: true
    has_many :member_backends, class_name: 'LightekPwa::MemberBackend', dependent: :restrict_with_error
    before_validation { self.request_key ||= SecureRandom.uuid }
    validates :status, inclusion: {in: %w[provisioning ready paused failed]}
    validates :max_members, numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: 100}
    validates :member_storage_bytes, numericality: {only_integer: true, greater_than_or_equal_to: 268435456, less_than_or_equal_to: 10737418240}
    validates :monthly_cost_ceiling_cents, numericality: {only_integer: true, greater_than: 0}
    def occupied = member_backends.where.not(status: %w[retired]).count
    def isolated!
      raise MemberBackends::Unavailable, 'Shared member hosting must use a separate remote server' unless node && !node.local? && operator.role == 'super_admin'
      central_nodes = GatekeeperProject.where(domain: site.host).pluck(:gatekeeper_node_id)
      central_nodes += GatekeeperInstallation.where(domain: site.host).pluck(:gatekeeper_node_id)
      raise MemberBackends::Unavailable, 'The central Lightek server cannot host free member backends' if central_nodes.include?(node.id) || node.hostname == site.host || node.metadata.to_h.fetch('website_deployments', {}).key?(site.host)
      true
    end
  end
end
