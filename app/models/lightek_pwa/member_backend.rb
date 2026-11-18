module LightekPwa
  class MemberBackend < ApplicationRecord
    self.table_name = 'lightek_pwa_member_backends'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :user
    belongs_to :shared_pool, class_name: 'LightekPwa::SharedPool', optional: true
    belongs_to :launch, class_name: 'GatekeeperApplicationLaunch', optional: true
    belongs_to :order, class_name: 'LightekCommerce::Order', optional: true
    has_one :peer, class_name: 'LightekReservations::Peer', dependent: :restrict_with_error
    before_validation { self.public_key ||= SecureRandom.uuid }
    validates :user_id, uniqueness: {scope: :site_id}
    validates :public_key, uniqueness: true, format: {with: /\A[0-9a-f-]{36}\z/}
    validates :status, inclusion: {in: %w[queued provisioning shared_ready migrating dedicated_ready failed retired]}
    validates :hosting_mode, inclusion: {in: %w[shared_account legacy_runtime]}
    def shared_account? = hosting_mode == 'shared_account'
    def source_runtime_hostname = shared_account? ? shared_pool.launch.domain : hostname
    def ready? = %w[shared_ready dedicated_ready].include?(status)
    def current_hostname = status == 'dedicated_ready' ? LightekCommerce::Installations.hostname(order) : hostname
    def current_node = status == 'dedicated_ready' ? order.gatekeeper_application_launch&.gatekeeper_node : shared_pool&.node
    def summary = {key: public_key, state: status, ready: ready?, hostname: current_hostname, error_code: error_code, mode: status == 'dedicated_ready' ? 'dedicated' : 'shared'}
  end
end
