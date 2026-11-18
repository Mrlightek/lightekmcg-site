module LightekPwa
  # A member gets a User and a logical Site in the pool's existing database.
  # Its hostname is an account route, not another Rails/Redis/Postgres runtime.
  class SharedAccounts
    def self.provision!(backend, connection:)
      pool = backend.shared_pool
      pool.isolated!
      launch = pool.launch
      raise MemberBackends::Unavailable, 'Shared hosting runtime must finish installation first' unless launch&.status == 'ready'
      profile = pool.node.metadata.to_h.fetch('website_deployments', {}).fetch(launch.domain).fetch('fleet_config')
      backend.update!(status: 'provisioning', error_code: nil)
      Gatekeeper::Hosting::Dns.prepare!(domain: backend.hostname, ip_address: pool.node.ip_address)
      secret = LightekVault::Service.checkout!(slug: connection.fetch('credential_slug'),
        consumer: 'Gatekeeper::WebsiteDeployment', purpose: 'reservation_federation', requested_by: pool.operator.email_address)
      # Retain uncertainty if SSH starts but its receipt is lost. A missing
      # credential must never rotate an account that might already be installed.
      backend.update!(account_receipt: backend.account_receipt.merge('installation_started' => true, 'shared_runtime' => launch.domain))
      receipt = Gatekeeper::Fleet::Transport.run!(node: pool.node, domain: launch.domain,
        requested_by: pool.operator.email_address, operation_id: nil, script_name: 'create_hosted_site.py', payload: {
          domain: backend.hostname, name: "#{backend.user.first_name}'s space", application_key: backend.public_key,
          owner_email: backend.user.email_address, certificate_email: pool.operator.email_address, deployment: profile,
          runtime_domain: launch.domain, runtime_owner_email: launch.owner.email_address,
          standby_runtime: standby_runtime(pool),
          owner: {first_name: backend.user.first_name, last_name: backend.user.last_name},
          pwa_member: {key: backend.public_key, origin: "https://#{backend.site.host}", mode: 'shared',
            hosting: 'shared_account', storage_bytes: pool.member_storage_bytes,
            display_name: backend.user.profile&.public_display_name.to_s.first(120).presence || 'Member'},
          reservation_federation: connection.merge('token' => secret.fetch('token'))})
      unless receipt['status'] == 'succeeded' && receipt['domain'] == backend.hostname &&
          receipt['application_key'] == backend.public_key && receipt['site_id'].to_i.positive? && receipt['shared_runtime'] == launch.domain
        raise MemberBackends::Unavailable, 'Shared account did not pass account routing verification'
      end
      backend.update!(status: 'shared_ready', account_receipt: receipt, error_code: nil)
      standby = receipt['standby_runtime']
      if pool.standby_launch && standby && standby['domain'] == pool.standby_launch.domain && %w[paused offline].include?(standby['state'])
        GatekeeperInstallation.where(gatekeeper_node_id: pool.node_id, domain: standby['domain']).update_all(enabled: false)
      end
      backend
    rescue Gatekeeper::Fleet::Transport::RemoteFailure
      raise MemberBackends::Unavailable, 'Shared hosting account setup needs retry on the existing runtime'
    ensure
      secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
    end
    def self.standby_runtime(pool)
      launch = pool.standby_launch
      return unless launch && launch.id != pool.launch_id && launch.gatekeeper_node_id == pool.node_id && launch.owner_id == pool.operator_id
      profile = pool.node.metadata.to_h.fetch('website_deployments', {}).fetch(launch.domain).fetch('fleet_config')
      {'domain' => launch.domain, 'owner_email' => pool.operator.email_address, 'deployment' => profile}
    end
  end
end
