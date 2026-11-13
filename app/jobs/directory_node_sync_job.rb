class DirectoryNodeSyncJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true if respond_to?(:enqueue_after_transaction_commit=)
  def perform(binding_id)
    binding = LightekIdentity::NodeBinding.find(binding_id)
    realm, node = binding.realm, binding.gatekeeper_node
    raise ArgumentError, 'Directory node ownership changed' unless node.owner_type == 'User' && node.owner_id == realm.employer_id && !node.local?
    LightekIdentity::DirectoryPolicy.calendar!(realm)
    members = LightekPeople::Employment.active.where(employer_id: realm.employer_id).includes(:worker)
    principals = realm.enabled? ? members.select { |member| LightekIdentity::Permissions.ids(member.worker,'GatekeeperNode','login').include?(node.id) }.map(&:directory_principal).select(&:present?) : []
    raise ArgumentError, 'Directory principal does not belong to this realm' unless principals.all? { |p| p.split('@').last.casecmp?(realm.domain) }
    revision = realm.directory_revision
    digest = Digest::SHA256.hexdigest(JSON.generate([realm.enabled?,principals.uniq.sort]))
    return if binding.synced_revision == revision && binding.policy_digest == digest
    payload = {action: 'sync', realm: realm.domain, binding_id: binding.id, principals: principals.uniq.sort, revision: revision, enabled: realm.enabled?}
    operation = GatekeeperOperation.create!(gatekeeper_node: node, capability: 'directory_membership', requested_by: realm.employer.email_address,
      status: 'running', started_at: Time.current, parameters: {binding_id: binding.id, realm_id: realm.id})
    receipt = Gatekeeper::Fleet::Transport.run!(node: node, domain: realm.domain, requested_by: realm.employer.email_address,
      operation_id: operation.id, payload: payload.dup, script_name: 'directory_membership.py')
    if receipt['status'] == 'needs_join' && realm.enabled?
      secret = LightekVault::Service.checkout!(slug: "directory-realm-#{realm.employer_id}", consumer: self.class.name, purpose: 'directory_join', requested_by: realm.employer.email_address, gatekeeper_operation_id: operation.id)
      receipt = Gatekeeper::Fleet::Transport.run!(node: node, domain: realm.domain, requested_by: realm.employer.email_address,
        operation_id: operation.id, payload: payload.merge(action: 'join', join_user: secret.fetch('username'), join_password: secret.fetch('password')), script_name: 'directory_membership.py')
    end
    if receipt['status'] == 'stale'
      DirectoryNodeSyncJob.perform_later(binding.id) if realm.reload.directory_revision > receipt['revision'].to_i
      operation.update!(status: 'succeeded',result: receipt,completed_at: Time.current,exit_status: 0)
      return
    end
    if realm.reload.directory_revision != revision
      DirectoryNodeSyncJob.perform_later(binding.id)
      operation.update!(status: 'succeeded',result: {'status'=>'superseded'},completed_at: Time.current,exit_status: 0)
      return
    end
    raise ArgumentError, 'Directory receipt did not verify' unless receipt['status'] == 'succeeded' && receipt['realm'] == realm.domain && receipt['binding_id'] == binding.id && receipt['principal_count'] == principals.uniq.length
    binding.update!(status: receipt['joined'] == false ? 'disabled' : 'joined', synced_at: Time.current, error_code: nil, synced_revision: revision, policy_digest: digest)
    operation.update!(status: 'succeeded', result: receipt, completed_at: Time.current, exit_status: 0)
  rescue StandardError => error
    binding&.with_lock do
      # An older failure must not overwrite a newer successful reconciliation.
      if revision && binding.synced_revision <= revision && binding.realm.reload.directory_revision == revision
        binding.update_columns(status: 'failed', error_code: error.class.name.demodulize)
      end
    end
    operation&.update_columns(status: 'failed', error_class: error.class.name, error_message: 'Directory reconciliation failed; credentials and subprocess output were suppressed.', completed_at: Time.current)
    raise
  ensure
    secret&.each_value { |v| v.clear if v.is_a?(String) && !v.frozen? }
  end
end
