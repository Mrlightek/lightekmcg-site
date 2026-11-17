require 'digest'
module LightekPwa
  class MemberBackends
    class Unavailable < StandardError; end
    def self.operator!(site, actor)
      raise Policy::Denied, 'Platform owner access required' unless actor&.role == 'super_admin' && site.tenant == actor
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
      pool = nil
      site.with_lock do
        existing = SharedPool.find_by(site: site, request_key: request_key)
        return existing if existing
        raise Unavailable, 'The shared host needs 6 GB disk per backend plus 10 GB for the host' unless plan['disk'].to_i >= Integer(max_members) * 6144 + 10240
        key = SecureRandom.hex(6)
        pool = SharedPool.create!(request_key: request_key, site: site, operator: actor, name: "Member hosting #{key}", max_members: max_members, monthly_cost_ceiling_cents: budget)
        launch = Gatekeeper::Hosting::Launches.create!(actor: actor, enqueue: false, attributes: {
          template_id: package.gatekeeper_application_template_id, compute_provider_id: package.compute_provider_id, owner_id: actor.id,
          name: pool.name, domain: "members-#{key}.#{site.host}", region: package.region, plan: package.provider_plan, monthly_cost_ceiling_cents: budget})
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
      return if site.tenant == user
      Policy.new(user: user, site: site).authorize!
      user.with_lock do
        existing = MemberBackend.find_by(site: site, user: user)
        if existing
          MemberBackendJob.perform_later(existing.id) unless existing.ready? || existing.status == 'migrating'
          return existing
        end
        # Never fall back to the central host when the pool is full or offline.
        SharedPool.where(site: site, status: 'ready').order(:id).each do |pool|
          result = pool.with_lock do
            pool.isolated!
            next if pool.occupied >= pool.max_members
            key = SecureRandom.uuid
            MemberBackend.create!(site: site, user: user, shared_pool: pool, public_key: key,
              hostname: "member-#{key.delete('-').first(20)}.#{site.host}")
          end
          if result
            MemberBackendJob.perform_later(result.id)
            return result
          end
        end
        raise Unavailable, 'Member hosting is at capacity. Your free account is preserved; new content waits for a separate host.'
      end
    end
    def self.connection!(backend)
      peer = backend.peer
      unless peer
        key = SecureRandom.uuid
        token = "#{key}.#{SecureRandom.hex(32)}"
        # The source server owns its content. This central row is discovery metadata only.
        remote_site = DymondSite::Site.find_or_initialize_by(host: backend.hostname)
        raise Unavailable, 'Member hostname is already owned' if remote_site.persisted? && remote_site.tenant != backend.user
        remote_site.assign_attributes(name: 'Member backend', tenant: backend.user); remote_site.save!
        LightekVault::Service.store!(name: 'Member backend connection', slug: "reservation-peer-#{key}", payload: {'token'=>token}, purpose: 'reservation_federation',
          access_policy: {'consumers'=>['LightekReservations::Federation::Issuer','Gatekeeper::WebsiteDeployment'], 'purposes'=>['reservation_federation']}, requested_by: backend.shared_pool.operator.email_address)
        peer = LightekReservations::Peer.create!(member_backend: backend, merchant: backend.user, site: remote_site, key: key, token_digest: Digest::SHA256.hexdigest(token))
      end
      {'origin'=>"https://#{backend.site.host}", 'client_host'=>backend.hostname, 'key'=>peer.key, 'credential_slug'=>"reservation-peer-#{peer.key}"}
    end
    def self.provision!(backend)
      return backend if backend.ready?
      pool = backend.shared_pool
      pool.isolated!
      raise Unavailable, 'Shared hosting is paused' unless pool.status == 'ready'
      backend.with_lock do
        unless backend.launch
          connection = connection!(backend)
          configuration = pool.launch.template_snapshot.merge('reservation_federation'=>connection,
            'pwa_member'=>{'key'=>backend.public_key, 'origin'=>"https://#{backend.site.host}", 'storage_bytes'=>pool.member_storage_bytes, 'mode'=>'shared'})
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
