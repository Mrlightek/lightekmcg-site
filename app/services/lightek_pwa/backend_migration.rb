require 'base64'
require 'digest'
module LightekPwa
  # Durable copy checkpoints; content bytes pass through memory and are never
  # saved in the discovery database or Gatekeeper operation results.
  class BackendMigration
    class Unavailable < StandardError; end
    def self.start!(order)
      purchase = Purchase.find_by(order: order)
      return unless purchase && LightekCommerce::Installations.ready?(order)
      backend = MemberBackend.find_by(site: purchase.site, user: purchase.user)
      return unless backend
      backend.with_lock do
        return backend if backend.status == 'dedicated_ready' && backend.order_id == order.id
        raise Unavailable, 'Another upgrade owns this backend' if backend.order_id && backend.order_id != order.id
        raise Unavailable, 'Shared backend must finish installation before upgrading' unless %w[shared_ready migrating].include?(backend.status)
        receipt = backend.migration_receipt.presence || {'operation_key'=>SecureRandom.uuid, 'state'=>'queued'}
        backend.update!(order: order, status: 'migrating', migration_receipt: receipt)
      end
      BackendMigrationJob.perform_later(backend.id)
      backend
    end
    def initialize(backend, for_restore: false)
      @backend = backend
      @order = backend.order
      @receipt = backend.migration_receipt.deep_dup
      @source_node = backend.shared_pool.node
      @target_node = @order.gatekeeper_application_launch&.gatekeeper_node || ProvisioningRequest.find_by(id: @order.provisioning_request_id)&.gatekeeper_node
      raise Unavailable, 'A separate paid server must pass installation first' unless @target_node && @target_node.id != @source_node.id && !@target_node.local? && (for_restore || LightekCommerce::Installations.ready?(@order))
      backend.shared_pool.isolated!
      @target_host = LightekCommerce::Installations.hostname(@order)
    end
    def remote(side, action, extra = {})
      node, host = side == :source ? [@source_node, @backend.hostname] : [@target_node, @target_host]
      profile = node.metadata.to_h.fetch('website_deployments', {}).fetch(host).fetch('fleet_config')
      payload = {'domain'=>host, 'member_key'=>@backend.public_key, 'owner_email'=>@backend.user.email_address,
        'operation_key'=>@receipt.fetch('operation_key'), 'deployment'=>profile, 'action'=>action}.merge(extra)
      # Transport clears the payload (including any chunk) on exit.
      Gatekeeper::Fleet::Transport.run!(node: node, domain: host, requested_by: @backend.shared_pool.operator.email_address,
        operation_id: nil, payload: payload, script_name: 'pwa_backend_transfer.py')
    end
    def checkpoint(state, values = {})
      @receipt = @receipt.merge(values).merge('state'=>state)
      @backend.update!(migration_receipt: @receipt, error_code: nil)
    end
    def execution_lock
      connection = ApplicationRecord.connection
      postgres = connection.adapter_name == 'PostgreSQL'
      key = 9_173_000_000 + @backend.id
      if postgres
        locked = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
        raise Unavailable, 'Another migration operation is running' unless locked == true || locked == 't'
      end
      @backend.reload
      @receipt = @backend.migration_receipt.deep_dup
      yield
    ensure
      connection.select_value("SELECT pg_advisory_unlock(#{key})") if postgres && locked
    end
    def perform! = execution_lock { run! }
    def run!
      return @backend if @backend.status == 'dedicated_ready' && @receipt['state'] == 'complete'
      raise Unavailable, 'Migration is not scheduled' unless %w[migrating dedicated_ready].include?(@backend.status)
      unless @receipt['target_reserved']
        raise Unavailable, 'Destination did not accept the write hold' unless remote(:target, 'reserve_target')['status'] == 'reserved'
        checkpoint('target_reserved', 'target_reserved'=>true)
      end
      unless @receipt['snapshot']
        snapshot = remote(:source, 'freeze_export')
        raise Unavailable, 'Source snapshot identity failed' unless snapshot['member_key'] == @backend.public_key && snapshot['status'] == 'frozen'
        checkpoint('copying', 'snapshot'=>snapshot)
      end
      snapshot = @receipt.fetch('snapshot')
      offset = @backend.copied_bytes
      while offset < snapshot.fetch('bytes')
        chunk = remote(:source, 'read_chunk', 'offset'=>offset)
        data = Base64.strict_decode64(chunk.fetch('data'))
        raise Unavailable, 'Invalid transfer chunk' unless data.bytesize.between?(1, 4.megabytes) && chunk['offset'] == offset && Digest::SHA256.hexdigest(data) == chunk['sha256'] && offset + data.bytesize <= snapshot['bytes']
        result = remote(:target, 'write_chunk', 'offset'=>offset, 'data'=>chunk.fetch('data'), 'chunk_sha256'=>chunk.fetch('sha256'))
        offset += data.bytesize
        raise Unavailable, 'Destination checkpoint differs' unless result['copied_bytes'] == offset
        @backend.update!(copied_bytes: offset)
      end
      unless %w[verified activated committed complete].include?(@receipt['state'])
        result = remote(:target, 'apply', snapshot.slice('bytes', 'sha256'))
        raise Unavailable, 'Destination did not verify the complete copy' unless result['status'] == 'verified' && result['sha256'] == snapshot['sha256'] && result['counts'] == snapshot['counts']
        checkpoint('verified')
      end
      if @receipt['state'] == 'verified'
        raise Unavailable, 'Paid membership changed before activation; restore the retained source' unless Purchase.find_by(order: @order)&.entitled?
        raise Unavailable, 'Destination did not activate' unless remote(:target, 'activate', 'managed_package'=>@order.items.sole.purchase_snapshot.to_h['managed_package'], 'plan_key'=>Purchase.find_by(order: @order)&.plan_key)['status'] == 'active'
        checkpoint('activated')
      end
      if @receipt['state'] == 'activated'
        # HTTPS health is independent of the root-SSH import receipt.
        verify_public_health!
        @backend.with_lock do
          peer = @backend.peer or raise Unavailable, 'Source discovery identity is missing'
          target_peer = LightekReservations::Peer.find_by(order: @order)
          if target_peer && target_peer.id != peer.id
            target_peer.update_columns(order_id: nil, enabled: false)
          end
          @receipt['previous_site_id'] ||= peer.site_id
          remote_site = DymondSite::Site.find_by!(host: @target_host, tenant: @backend.user)
          peer.update!(order: @order, site: remote_site)
          PublicationReference.where(peer: peer).includes(:post).each do |ref|
            post = ref.post
            next unless post
            meta = post.metadata.deep_dup
            content = meta.fetch('remote_content')
            content['fetch_url'] = "https://#{@target_host}/api/lightek/network/posts/#{ref.remote_post_id}"
            content['post_url'] = "https://#{@target_host}/lightek/index.html#/post/#{ref.remote_post_id}"
            post.update!(metadata: meta)
          end
          @receipt['state'] = 'committed'
          @backend.update!(status: 'dedicated_ready', migration_receipt: @receipt, retire_after: 7.days.from_now, error_code: nil)
        end
      end
      if @receipt['state'] == 'committed'
        # Source remains frozen and retained. A retry only installs its redirect.
        raise Unavailable, 'Source routing cutover needs retry' unless remote(:source, 'redirect', 'destination_hostname'=>@target_host)['status'] == 'redirecting'
        notify_ready!
        checkpoint('complete', 'completed_at'=>Time.current.iso8601)
      end
      @backend
    end
    def notify_ready!
      LightekCommerce::PaidInstanceProvisioning.publish_ready_notification!(order: @order, customer: @backend.user, domain: @target_host)
    end
    def verify_public_health!
      require 'net/http'
      uri = URI("https://#{@target_host}/api/lightek/pwa/backend-health")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.get(uri.request_uri) }
      raise Unavailable, 'The migrated backend did not pass public HTTPS health' unless response.is_a?(Net::HTTPSuccess) && response.body.bytesize < 32_768
      data = JSON.parse(response.body)
      raise Unavailable, 'The migrated backend identity differs' unless data['member_key'] == @backend.public_key
      managed = @order.items.sole.purchase_snapshot.to_h['managed_package']
      if managed
        raise Unavailable, 'The purchased package was not activated on the destination' unless data['package_digest'] == LightekAgency::PackagePolicy.digest(managed.fetch('policy'))
      end
    end
    def rollback! = execution_lock { restore! }
    def restore!
      # Once activated, new posts may exist on the destination. Never discard
      # them by sending writes to an older snapshot; require a reverse transfer.
      raise Unavailable, 'Destination may contain new writes; reconcile before reversing the move' if %w[activated committed complete].include?(@receipt['state']) || @backend.status == 'dedicated_ready'
      raise Unavailable, 'Destination could not be safely restored' unless remote(:target, 'abort_target')['status'] == 'aborted'
      remote(:source, 'rollback_source')
      @backend.update!(status: 'shared_ready', order: nil, copied_bytes: 0, migration_receipt: {}, error_code: nil)
    end
  end
end
