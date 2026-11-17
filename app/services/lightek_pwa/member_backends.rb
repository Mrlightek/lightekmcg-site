require 'digest'
module LightekPwa
  class MemberBackends
    class Unavailable < StandardError; end
    def self.operator!(site, actor)
      Policy.authorize_platform!(user: actor, site: site)
    end
    def self.smallest_plan!(plans)
      plans.select { |plan| plan['monthly_cents'].to_i.positive? && plan['memory'].to_i >= 1024 && plan['disk'].to_i >= 16384 }
        .min_by { |plan| [plan['memory'].to_i, plan['monthly_cents'].to_i, plan['vcpus'].to_i, plan['id'].to_s] } ||
        raise(Unavailable, 'No priced server can safely run a shared member backend')
    end
    def self.smallest_offer!(actor:, region:)
      raise Policy::Denied, 'Platform super administrator access required' unless actor&.role == 'super_admin'
      provider = ComputeProvider.active.where(slug: 'linode', health_status: 'healthy').order(:id).first or raise Unavailable, 'Connect a healthy compute provider first'
      catalog = Gatekeeper::Compute::LinodeCatalogService.call(provider: provider, requested_by: actor.email_address, region: region)
      raise Unavailable, 'Choose a supported provider region' unless catalog.fetch('regions').any? { |row| row['id'] == region }
      plan = smallest_plan!(catalog.fetch('plans'))
      {provider: provider, plan: plan, region: region,
        capacity: 1}
    end
    def self.create_smallest_pool!(site:, actor:, region:, plan_id:, monthly_cents:, request_key:)
      operator!(site, actor)
      offer = smallest_offer!(actor: actor, region: region)
      plan = offer.fetch(:plan)
      raise Unavailable, 'The smallest server or its price changed. Review the new quote before creating it.' unless plan['id'] == plan_id && plan['monthly_cents'] == monthly_cents
      template = GatekeeperApplicationTemplate.ensure_native!
      create_host!(site: site, actor: actor, max_members: offer.fetch(:capacity), budget: monthly_cents, request_key: request_key,
        attributes: {template_id: template.id, compute_provider_id: offer.fetch(:provider).id, region: region, plan: plan_id,
          template_configuration: template.attributes.slice('kind', 'image', 'container_port', 'credential_slug', 'rails_database', 'rails_worker', 'lightek_application').merge('pwa_pool' => {'profile' => 'starter'})})
    end
    def self.create_pool!(site:, actor:, package:, max_members:, monthly_budget_cents:, request_key: SecureRandom.uuid)
      operator!(site, actor)
      raise Unavailable, 'Choose an active native hosting package' unless package.active? && package.product.site == site && package.gatekeeper_application_template.kind == 'native_rails'
      budget = Integer(monthly_budget_cents)
      raise Unavailable, 'The selected server exceeds the approved monthly budget' if package.monthly_cost_ceiling_cents > budget
      catalog = Gatekeeper::Compute::LinodeCatalogService.call(provider: package.compute_provider, requested_by: actor.email_address, region: package.region)
      plan = catalog.fetch('plans').find { |p| p['id'] == package.provider_plan } or raise Unavailable, 'The shared hosting plan is unavailable'
      raise Unavailable, 'The shared host needs at least 1.5 GB per member plus 1 GB for the host' unless plan['memory'].to_i >= Integer(max_members) * 1536 + 1024
      raise Unavailable, 'Provider price exceeds the approved monthly budget' unless plan['monthly_cents'].to_i.positive? && plan['monthly_cents'].to_i <= budget
      raise Unavailable, 'Invalid shared-host request identity' unless request_key.to_s.match?(/\A[0-9a-f-]{36}\z/)
      raise Unavailable, 'The shared host needs 6 GB disk per backend plus 10 GB for the host' unless plan['disk'].to_i >= Integer(max_members) * 6144 + 10240
      create_host!(site: site, actor: actor, max_members: max_members, budget: budget, request_key: request_key,
        attributes: {template_id: package.gatekeeper_application_template_id, compute_provider_id: package.compute_provider_id, region: package.region, plan: package.provider_plan})
    end
    def self.create_host!(site:, actor:, max_members:, budget:, request_key:, attributes:)
      operator!(site, actor)
      raise Unavailable, 'Invalid shared-host request identity' unless request_key.to_s.match?(/\A[0-9a-f-]{36}\z/)
      pool = nil
      site.with_lock do
        existing = SharedPool.find_by(site: site, request_key: request_key)
        return existing if existing
        Policy.bind_platform!(site: site, actor: actor)
        key = SecureRandom.hex(6)
        pool = SharedPool.create!(request_key: request_key, site: site, operator: actor, name: "Member hosting #{key}", max_members: max_members, monthly_cost_ceiling_cents: budget,
          member_storage_bytes: attributes.dig(:template_configuration, 'pwa_pool', 'profile') == 'starter' ? 268435456 : 536870912)
        launch = Gatekeeper::Hosting::Launches.create!(actor: actor, enqueue: false,
          attributes: attributes.merge(owner_id: actor.id, name: pool.name, domain: "members-#{key}.#{site.host}", monthly_cost_ceiling_cents: budget))
        pool.update!(launch: launch)
      end
      MemberPoolJob.perform_later(pool.id)
      pool
    end
    def self.recover_stale_launch!(launch)
      launch.with_lock do
        # Caller holds the backend/pool session lock. A previous SSH installer
        # must also acquire the same native site lock before touching files.
        launch.update!(status: 'failed') if launch.status == 'provisioning' && launch.updated_at < 45.minutes.ago
      end
    end
    def self.refresh_pool!(pool)
      recover_stale_launch!(pool.launch)
      Gatekeeper::Hosting::Launches.perform!(pool.launch) unless pool.launch.status == 'ready'
      raise Unavailable, 'Shared hosting installation is still being prepared' unless pool.launch.reload.status == 'ready'
      pool.update!(node: pool.launch.gatekeeper_node)
      pool.isolated!
      pool.update!(status: 'ready')
      pool
    end
    def self.reserve!(site:, user:)
      return if user&.role == 'super_admin'
      Policy.new(user: user, site: site).authorize!
      raise Unavailable, 'Your paid instance already provides your publishing space. Open My instance to sign in.' if Plans.current(user, site) && !MemberBackend.exists?(site: site, user: user)
      user.with_lock do
        existing = MemberBackend.find_by(site: site, user: user)
        if existing
          MemberBackendJob.perform_later(existing.id) unless existing.ready? || existing.status == 'migrating'
          return existing
        end
        # Serialize only placement, not native/cloud setup. The durable cursor
        # advances with the reservation and ignores paused/full/invalid pools.
        site.with_lock do
          routing = site.manifest.to_h.fetch('pwa_pool_routing', {})
          pools = SharedPool.where(site: site, status: 'ready').order(:id).to_a
          if routing['mode'] == 'round_robin'
            cursor = routing['last_pool_id'].to_i
            pools = pools.select { |pool| pool.id > cursor } + pools.select { |pool| pool.id <= cursor }
          elsif routing['default_pool_id'].present?
            pools.select! { |pool| pool.id == routing['default_pool_id'].to_i }
          end
          pools.each do |pool|
            result = pool.with_lock do
              begin
                pool.isolated!
              rescue Unavailable
                next
              end
              next if pool.occupied >= pool.max_members
              key = SecureRandom.uuid
              MemberBackend.create!(site: site, user: user, shared_pool: pool, public_key: key,
                hostname: "member-#{key.delete('-').first(20)}.#{site.host}")
            end
            if result
              if routing['mode'] == 'round_robin'
                site.update!(manifest: site.manifest.to_h.merge('pwa_pool_routing' => routing.merge('last_pool_id' => pool.id)))
              end
              MemberBackendJob.perform_later(result.id)
              return result
            end
          end
        end
        raise Unavailable, 'Member hosting is at capacity. Your free account is preserved; new content waits for a separate host.'
      end
    end
    def self.configure_routing!(site:, actor:, mode:, default_pool_id: nil)
      operator!(site, actor)
      raise Unavailable, 'Choose a default server or round robin' unless %w[default round_robin].include?(mode)
      site.with_lock do
        pool = SharedPool.where(site: site, status: 'ready').find(default_pool_id) if default_pool_id.present?
        pool&.isolated!
        raise Unavailable, 'Choose a ready default free-member server' if mode == 'default' && !pool
        site.update!(manifest: site.manifest.to_h.merge('pwa_pool_routing' => {'mode' => mode, 'default_pool_id' => pool&.id}))
      end
    end
    def self.set_pool_status!(site:, actor:, pool_id:, status:)
      operator!(site, actor)
      raise Unavailable, 'Choose pause or resume' unless %w[ready paused].include?(status)
      site.with_lock do
        pool = SharedPool.where(site: site).find(pool_id)
        pool.with_lock do
          raise Unavailable, 'Only an installed shared server can be paused or resumed' unless pool.status.in?(%w[ready paused]) && pool.launch&.status == 'ready'
          pool.isolated!
          pool.update!(status: status)
        end
      end
    end
    def self.connection!(backend)
      peer = backend.peer
      # This central row is discovery metadata, not an installed website. Do
      # not let it consume the hostname before Launches creates the real site.
      remote_site = DymondSite::Site.find_or_initialize_by(host: backend.hostname)
      if remote_site.persisted?
        raise Unavailable, 'Member hostname is already owned' unless remote_site.tenant == backend.user
        if peer
          raise Unavailable, 'Member connection identity mismatch' unless peer.site_id == remote_site.id && peer.merchant_id == backend.user_id
        elsif remote_site.manifest.to_h['network_ledger'] != true
          raise Unavailable, 'Member hostname is already assigned to a website'
        end
      end
      remote_site.assign_attributes(name: 'Member backend', tenant: backend.user,
        manifest: remote_site.manifest.to_h.merge('network_ledger' => true))
      remote_site.save!
      if !peer
        key = SecureRandom.uuid
        # The source server owns its content. This central row is discovery metadata only.
        digest = store_peer_credential!(backend: backend, key: key)
        peer = LightekReservations::Peer.create!(member_backend: backend, merchant: backend.user, site: remote_site, key: key, token_digest: digest)
      elsif !LightekVault::Secret.exists?(slug: "reservation-peer-#{peer.key}")
        launch = backend.launch
        # Recover only a never-installed backend. Do not rotate a live peer,
        # replace a disabled credential, or race an installer already running.
        unless backend.status.in?(%w[queued provisioning]) && (!launch || (launch.status.in?(%w[queued failed]) && launch.receipt.blank?))
          raise Unavailable, 'Member connection credential is missing; an installed backend requires operator review'
        end
        peer.update!(token_digest: store_peer_credential!(backend: backend, key: peer.key))
      end
      {'origin'=>"https://#{backend.site.host}", 'client_host'=>backend.hostname, 'key'=>peer.key, 'credential_slug'=>"reservation-peer-#{peer.key}"}
    end
    def self.store_peer_credential!(backend:, key:)
      token = "#{key}.#{SecureRandom.hex(32)}"
      LightekVault::Service.store!(name: 'Member backend connection', slug: "reservation-peer-#{key}", payload: {'token'=>token}, purpose: 'reservation_federation',
        access_policy: {'consumers'=>['LightekReservations::Federation::Issuer','Gatekeeper::WebsiteDeployment'], 'purposes'=>['reservation_federation']}, requested_by: backend.shared_pool.operator.email_address)
      Digest::SHA256.hexdigest(token)
    ensure
      token&.clear
    end
    def self.provision!(backend)
      return backend if backend.ready?
      pool = backend.shared_pool
      pool.isolated!
      raise Unavailable, 'Shared hosting is unavailable' unless pool.status.in?(%w[ready paused])
      backend.with_lock do
        # Retry must validate the federation credential even after a launch
        # record has been allocated; the installer still needs that credential.
        connection = connection!(backend)
        unless backend.launch
          configuration = pool.launch.template_snapshot.merge('reservation_federation'=>connection,
            'pwa_member'=>{'key'=>backend.public_key, 'origin'=>"https://#{backend.site.host}", 'storage_bytes'=>pool.member_storage_bytes, 'mode'=>'shared', 'display_name'=>backend.user.profile&.public_display_name.to_s.first(120).presence || 'Member'})
          launch = Gatekeeper::Hosting::Launches.create!(actor: pool.operator, enqueue: false, attributes: {template_id: pool.launch.gatekeeper_application_template_id,
            node_id: pool.node_id, owner_id: backend.user_id, name: "#{backend.user.first_name}'s space", domain: backend.hostname, template_configuration: configuration})
          backend.update!(launch: launch, status: 'provisioning', error_code: nil)
        end
      end
      recover_stale_launch!(backend.launch)
      Gatekeeper::Hosting::Launches.perform!(backend.launch)
      raise Unavailable, 'Member backend has not passed native installation verification' unless backend.launch.reload.status == 'ready'
      raise Unavailable, 'Member backend escaped its separate shared host' unless backend.launch.gatekeeper_node_id == pool.node_id
      backend.update!(status: 'shared_ready', error_code: nil)
      backend
    end
    def self.issue_ticket!(backend:, user:)
      raise Policy::Denied, 'This backend belongs to another member' unless backend.user == user && backend.ready?
      Policy.new(user: user, site: backend.site).authorize!
      token = SecureRandom.hex(32)
      MemberTicket.create!(member_backend: backend, token_digest: Digest::SHA256.hexdigest(token), expires_at: 90.seconds.from_now)
      "https://#{backend.current_hostname}/pwa/member-session?ticket=#{token}"
    end
    def self.redeem_ticket!(peer:, token:)
      backend = peer.member_backend or raise Policy::Denied, 'Not a member backend'
      raise Policy::Denied, 'Member backend is not ready' unless backend.ready?
      ticket = MemberTicket.find_by!(member_backend: backend, token_digest: Digest::SHA256.hexdigest(token.to_s))
      ticket.with_lock do
        raise Policy::Denied, 'This sign-in link has expired or was already used' unless ticket.expires_at.future? && !ticket.redeemed_at
        Policy.new(user: backend.user, site: backend.site).authorize!
        ticket.update!(redeemed_at: Time.current)
        {email: backend.user.email_address, backend_key: backend.public_key, hostname: backend.current_hostname}
      end
    end
  end
end
