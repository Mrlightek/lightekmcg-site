require_relative 'pwa_commercial_checks'
ActiveRecord::Schema.define do
  add_column :lightek_commerce_orders, :provisioning_request_id, :integer
  create_table(:lightek_agency_installed_packages) { |t| t.integer :user_id; t.string :source_key; t.boolean :runtime; t.json :policy, default: {} }
  create_table(:agency_profiles) { |t| t.integer :user_id; t.string :brand_name; t.string :accent_color, default: '#d4af37'; t.string :logo_url; t.string :support_email }
  create_table(:gatekeeper_nodes) { |t| t.string :hostname; t.json :metadata, default: {}; t.boolean :local, default: false }
  create_table(:gatekeeper_application_launches) { |t| t.integer :gatekeeper_node_id; t.string :status }
  create_table(:gatekeeper_projects) { |t| t.string :domain; t.integer :gatekeeper_node_id }
  create_table(:gatekeeper_installations) { |t| t.string :domain; t.integer :gatekeeper_node_id }
  add_column :gatekeeper_nodes, :owner_type, :string
  add_column :gatekeeper_nodes, :owner_id, :integer
  add_column :gatekeeper_nodes, :status, :string
  add_column :gatekeeper_application_launches, :owner_id, :integer
  add_column :gatekeeper_application_launches, :domain, :string
  add_column :gatekeeper_application_launches, :receipt, :json, default: {}
  create_table(:gatekeeper_hosted_applications) { |t| t.integer :owner_id; t.string :domain; t.string :status }
end
# Cloud request lookup is outside this fixture; completed orders need no request.
class ProvisioningRequest
  def self.find_by(*) = nil
end
LightekCommerce::Order.reset_column_information
class GatekeeperNode < ApplicationRecord
  def local? = local
end
class GatekeeperApplicationLaunch < ApplicationRecord
  belongs_to :gatekeeper_node
end
class GatekeeperProject < ApplicationRecord; end
class GatekeeperInstallation < ApplicationRecord; end
class GatekeeperHostedApplication < ApplicationRecord; end
require File.join(ROOT, 'app/services/gatekeeper/hosting/access')
# Encrypted Vault persistence is outside this backend/hostname fixture.
module LightekVault
  class Secret
    class << self; attr_accessor :records; end
    self.records = {}
    def self.exists?(slug:) = records.key?(slug)
  end
  class Service
    def self.store!(slug:, payload:, **) = Secret.records[slug] = Digest::SHA256.hexdigest(payload.fetch('token'))
  end
end
require File.join(ROOT, 'app/services/lightek_agency/package_policy')
require File.join(ROOT, 'app/models/lightek_agency/installed_package')
require File.join(ROOT, 'app/models/agency_profile')
class User
  has_one :agency_profile
end
require File.join(ROOT, 'app/services/lightek_pwa/native_backend')
require File.join(ROOT, 'db/migrate/20261117140000_create_pwa_member_backends')
CreatePwaMemberBackends.new.migrate(:up)
LightekReservations::Peer.reset_column_information
%w[shared_pool member_backend member_ticket].each { |name| require File.join(ROOT, "app/models/lightek_pwa/#{name}") }
%w[member_backends backend_migration source_runtime].each { |name| require File.join(ROOT, "app/services/lightek_pwa/#{name}") }
module LightekPwa
  class MemberBackendJob
    def self.perform_later(*) = true
  end
end
class PwaMemberBackendTest < PwaCommercialTest
  PwaCommercialTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def setup
    super
    LightekVault::Secret.records.clear
    @node = GatekeeperNode.create!(hostname: 'shared.test')
    @pool = LightekPwa::SharedPool.create!(site: @site, operator: @operator, node: @node,
      name: 'Separate members', status: 'ready', max_members: 1, monthly_cost_ceiling_cents: 2400)
  end
  def test_free_backend_capacity_is_durable_and_has_no_central_fallback
    @purchase.destroy!
    first = LightekPwa::MemberBackends.reserve!(site: @site, user: @owner)
    assert_equal @pool, first.shared_pool
    assert_equal first, LightekPwa::MemberBackends.reserve!(site: @site, user: @owner)
    other = User.create!(role: 'client')
    assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.reserve!(site: @site, user: other) }
    assert_equal 1, LightekPwa::MemberBackend.count
    assert_equal 0, Post.where(user: other).count
  end
  def test_discovery_record_does_not_reserve_the_installation_hostname
    @purchase.destroy!
    record = LightekPwa::MemberBackends.reserve!(site: @site, user: @owner)
    result = LightekPwa::MemberBackends.connection!(record)
    site = DymondSite::Site.find_by!(host: record.hostname)
    assert_equal true, site.manifest['network_ledger']
    assert_equal @owner, site.tenant
    assert_equal record.hostname, result['client_host']
    refute_includes Gatekeeper::Hosting::Access.site_domains(@owner), record.hostname
    # A real launch still owns its hostname even when a discovery row exists.
    GatekeeperApplicationLaunch.create!(gatekeeper_node: @node, owner_id: @owner.id, domain: record.hostname, status: 'queued')
    assert_includes Gatekeeper::Hosting::Access.site_domains(@owner), record.hostname
  end
  def test_retry_repairs_only_its_existing_discovery_record_without_rotating_peer
    record = backend
    site = DymondSite::Site.create!(host: record.hostname, tenant: @owner, name: 'Member backend', manifest: {'keep' => 'value'})
    peer = LightekReservations::Peer.create!(member_backend: record, merchant: @owner, site: site, key: SecureRandom.uuid, token_digest: 'b'*64)
    LightekVault::Secret.records["reservation-peer-#{peer.key}"] = 'b'*64
    LightekPwa::MemberBackends.connection!(record)
    assert_equal({'keep'=>'value', 'network_ledger'=>true}, site.reload.manifest)
    assert_equal peer.id, record.reload.peer.id
    assert_equal 'b'*64, record.peer.token_digest
    refute_includes Gatekeeper::Hosting::Access.site_domains(@owner), record.hostname
  end
  def test_missing_credential_is_recovered_before_retrying_an_existing_failed_launch
    record = backend
    record.update!(status: 'provisioning')
    LightekPwa::MemberBackends.connection!(record)
    peer = record.reload.peer
    original_digest = peer.token_digest
    LightekVault::Secret.records.clear
    launch = GatekeeperApplicationLaunch.create!(gatekeeper_node: @node, owner_id: @owner.id, domain: record.hostname, status: 'failed')
    record.update!(launch: launch)
    # Remote installer is the boundary; actual retry and credential recovery run.
    launches = Class.new do
      def self.perform!(launch) = launch.update!(status: 'ready')
    end
    Gatekeeper::Hosting.const_set(:Launches, launches)
    LightekPwa::MemberBackends.provision!(record)
    assert record.reload.ready?
    assert_equal launch.id, record.launch_id
    assert_equal peer.id, record.peer.id
    refute_equal original_digest, record.peer.token_digest
    assert_equal LightekVault::Secret.records.fetch("reservation-peer-#{peer.key}"), record.peer.token_digest
  ensure
    Gatekeeper::Hosting.send(:remove_const, :Launches) if launches
  end
  def test_missing_live_peer_credential_is_not_silently_rotated
    record = backend
    LightekPwa::MemberBackends.connection!(record)
    digest = record.reload.peer.token_digest
    LightekVault::Secret.records.clear
    assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.connection!(record) }
    assert_equal digest, record.peer.reload.token_digest
    assert_empty LightekVault::Secret.records
  end
  def test_recovery_does_not_race_installation_or_replace_a_receipted_connection
    record = backend
    record.update!(status: 'provisioning')
    LightekPwa::MemberBackends.connection!(record)
    digest = record.reload.peer.token_digest
    LightekVault::Secret.records.clear
    [['provisioning', {}], ['failed', {'verified'=>true}], ['ready', {}]].each do |status, receipt|
      launch = GatekeeperApplicationLaunch.create!(gatekeeper_node: @node, owner_id: @owner.id, domain: record.hostname, status: status, receipt: receipt)
      record.update!(launch: launch)
      assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.connection!(record) }
      assert_equal digest, record.peer.reload.token_digest
      assert_empty LightekVault::Secret.records
    end
  end
  def test_existing_real_website_and_foreign_owner_cannot_be_reclassified
    record = backend
    site = DymondSite::Site.create!(host: record.hostname, tenant: @owner, name: 'Real website', manifest: {})
    assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.connection!(record) }
    refute site.reload.manifest['network_ledger']
    site.update!(tenant: @operator)
    assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.connection!(record) }
    assert_equal @operator, site.reload.tenant
  end
  def test_existing_paid_members_do_not_allocate_redundant_free_backends
    assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.reserve!(site: @site, user: @owner) }
    assert_empty LightekPwa::MemberBackend.all
    destination = LightekPwa::Network.write_destination(user: @owner, site: @site)
    assert_equal 'https://member.test/lightek/index.html#/create', destination[:create_url]
  end
  def test_central_host_is_rejected_from_every_inventory_source
    @node.update!(local: true)
    assert_raises(LightekPwa::MemberBackends::Unavailable) { @pool.isolated! }
    @node.update!(local: false, hostname: @site.host)
    assert_raises(LightekPwa::MemberBackends::Unavailable) { @pool.isolated! }
    @node.update!(hostname: 'shared.test', metadata: {'website_deployments'=>{@site.host=>{}}})
    assert_raises(LightekPwa::MemberBackends::Unavailable) { @pool.isolated! }
    @node.update!(metadata: {})
    GatekeeperProject.create!(domain: @site.host, gatekeeper_node_id: @node.id)
    assert_raises(LightekPwa::MemberBackends::Unavailable) { @pool.isolated! }
  end
  def backend
    @backend ||= LightekPwa::MemberBackend.create!(site: @site, user: @owner, shared_pool: @pool, hostname: 'free.test', status: 'shared_ready')
  end
  def test_free_peer_can_publish_only_for_its_backend_owner
    @peer.update!(order: nil, member_backend: backend)
    assert @peer.active?
    ref = publish
    assert_nil ref.post.content
    assert_equal 'https://free.test/api/lightek/network/posts/17', ref.post.metadata.dig('remote_content', 'fetch_url')
    @peer.update!(merchant: @operator)
    assert_raises(LightekPwa::Policy::Denied) { publish(revision: 2, removed: true) }
    assert ref.reload.post
  end
  def test_single_use_expiring_tickets_cannot_be_replayed_or_used_by_other_members
    @peer.update!(order: nil, member_backend: backend)
    url = LightekPwa::MemberBackends.issue_ticket!(backend: backend, user: @owner)
    token = URI.decode_www_form(URI(url).query).to_h.fetch('ticket')
    refute_equal token, LightekPwa::MemberTicket.last.token_digest
    data = LightekPwa::MemberBackends.redeem_ticket!(peer: @peer, token: token)
    assert_equal backend.public_key, data[:backend_key]
    assert_raises(LightekPwa::Policy::Denied) { LightekPwa::MemberBackends.redeem_ticket!(peer: @peer, token: token) }
    assert_raises(LightekPwa::Policy::Denied) { LightekPwa::MemberBackends.issue_ticket!(backend: backend, user: @operator) }
    url = LightekPwa::MemberBackends.issue_ticket!(backend: backend, user: @owner)
    LightekPwa::MemberTicket.last.update!(expires_at: 1.second.ago)
    assert_raises(LightekPwa::Policy::Denied) { LightekPwa::MemberBackends.redeem_ticket!(peer: @peer, token: URI.decode_www_form(URI(url).query).to_h.fetch('ticket')) }
  end
  def test_destination_activation_reapplies_paid_policy_and_business_identity_after_copy
    @remote.update!(manifest: {'pwa_member'=>{'key'=>backend.public_key, 'mode'=>'dedicated'}})
    configuration = {'source_key'=>'paid-order-1', 'policy'=>{'features'=>{'agency'=>{'enabled'=>true}, 'studio'=>{'enabled'=>false}}}}
    input = {'domain'=>@remote.host, 'owner_email'=>@owner.email_address, 'member_key'=>backend.public_key, 'managed_package'=>configuration, 'plan_key'=>'business'}
    2.times { LightekPwa::NativeBackend.activate!(input) }
    assert_equal 'white_label', @owner.reload.role
    assert_equal 'Creator', @owner.agency_profile.brand_name
    assert_equal 1, AgencyProfile.count
    installed = LightekAgency::InstalledPackage.sole
    assert_equal 'paid-order-1', installed.source_key
    refute installed.policy.dig('features', 'studio', 'enabled')
    assert_equal LightekAgency::PackagePolicy.digest(configuration['policy']), @remote.reload.manifest.dig('pwa_member', 'paid_package_digest')
  end
  def test_old_source_cannot_be_reenabled_after_destination_can_receive_writes
    backend.update!(status: 'migrating', order: @order, migration_receipt: {'operation_key'=>SecureRandom.uuid, 'state'=>'activated', 'snapshot'=>{'bytes'=>10}})
    migration = LightekPwa::BackendMigration.allocate
    migration.instance_variable_set(:@backend, backend)
    migration.instance_variable_set(:@receipt, backend.migration_receipt)
    assert_raises(LightekPwa::BackendMigration::Unavailable) { migration.rollback! }
    assert_equal 'migrating', backend.reload.status
  end
  def migration_fixture
    @peer.update!(order: nil, member_backend: backend)
    @migration_ref = publish
    backend.update!(order: @order, status: 'migrating', migration_receipt: {'operation_key'=>SecureRandom.uuid, 'state'=>'queued'})
    source_site = DymondSite::Site.create!(name: 'Free source', host: backend.hostname, tenant: @owner)
    @peer.update!(order: nil, member_backend: backend, site: source_site)
    target_node = GatekeeperNode.create!(hostname: 'dedicated.test')
    launch = Struct.new(:gatekeeper_node).new(target_node)
    @order.define_singleton_method(:gatekeeper_application_launch) { launch }
    @order.define_singleton_method(:items) { [Struct.new(:purchase_snapshot).new({})] }
    backend.order = @order
    @migration_bytes = 'complete database and original media'
    @snapshot = {'member_key'=>backend.public_key, 'status'=>'frozen', 'bytes'=>@migration_bytes.bytesize,
      'sha256'=>Digest::SHA256.hexdigest(@migration_bytes), 'counts'=>{'posts'=>1}, 'storage_sha256'=>'a'*64, 'source_sha'=>'b'*40}
    migration = LightekPwa::BackendMigration.new(backend)
    migration.define_singleton_method(:notify_ready!) {}
    migration
  end
  def migration_rpc(side, action, extra={})
    case action
    when 'reserve_target' then {'status'=>'reserved'}
    when 'freeze_export' then @snapshot
    when 'read_chunk' then {'offset'=>0,'data'=>Base64.strict_encode64(@migration_bytes),'sha256'=>Digest::SHA256.hexdigest(@migration_bytes)}
    when 'write_chunk' then {'copied_bytes'=>@migration_bytes.bytesize}
    when 'apply' then {'status'=>'verified','sha256'=>@snapshot['sha256'],'counts'=>@snapshot['counts']}
    when 'activate' then {'status'=>'active'}
    when 'redirect' then {'status'=>'redirecting'}
    else raise "Unexpected transfer action #{action}"
    end
  end
  def test_verified_upgrade_keeps_discovery_post_identity_and_moves_only_reference_urls
    migration = migration_fixture
    ref = @migration_ref
    central_id = ref.post_id
    migration.stub(:remote, method(:migration_rpc)) do
      migration.stub(:verify_public_health!, true) { migration.perform! }
    end
    assert_equal 'dedicated_ready', backend.reload.status
    assert_equal 'complete', backend.migration_receipt['state']
    assert_equal @migration_bytes.bytesize, backend.copied_bytes
    assert_equal @order.id, @peer.reload.order_id
    assert_equal central_id, ref.reload.post_id
    assert_equal 'https://member.test/api/lightek/network/posts/17', ref.post.metadata.dig('remote_content','fetch_url')
    assert_nil ref.post.content
    assert backend.retire_after > 6.days.from_now
    refute backend.migration_receipt.to_json.include?(Base64.strict_encode64(@migration_bytes))
  end
  def test_paid_access_waits_for_member_content_and_nonempty_destination_never_freezes_source
    migration = migration_fixture
    summary = LightekCommerce::Installations.summary(@order)
    assert_equal 'moving_content', summary[:state]
    refute summary[:ready]
    assert_nil summary[:url]
    actions = []
    migration.stub(:remote, ->(side, action, extra={}) {actions << action; raise LightekPwa::BackendMigration::Unavailable, 'Destination already contains content'}) do
      assert_raises(LightekPwa::BackendMigration::Unavailable) { migration.perform! }
    end
    assert_equal ['reserve_target'], actions
    assert_nil backend.reload.migration_receipt['snapshot']
  end
  def test_restore_before_source_snapshot_preserves_both_runtimes
    migration = migration_fixture
    actions = []
    rpc = lambda do |side, action, extra={}|
      actions << [side, action]
      action == 'abort_target' ? {'status'=>'aborted'} : {'status'=>'active'}
    end
    migration.stub(:remote, rpc) { migration.rollback! }
    assert_equal [[:target, 'abort_target'], [:source, 'rollback_source']], actions
    assert_equal 'shared_ready', backend.reload.status
    assert_nil backend.order_id
  end
  def test_failed_destination_verification_keeps_source_routing_and_prevents_activation
    migration = migration_fixture
    rpc = lambda do |side, action, extra={}|
      raise LightekPwa::BackendMigration::Unavailable, 'Checksum mismatch' if action == 'apply'
      raise 'Never activate a failed import' if action == 'activate'
      migration_rpc(side, action, extra)
    end
    migration.stub(:remote, rpc) { assert_raises(LightekPwa::BackendMigration::Unavailable) { migration.perform! } }
    assert_nil @peer.reload.order_id
    assert_equal 'migrating', backend.reload.status
    assert_equal 'copying', backend.migration_receipt['state']
  end

end

require File.join(ROOT, 'lib/middleware/pwa_member_guard')
require File.join(ROOT, 'app/models/concerns/pwa_member_storage_quota')
ActiveStorage::Blob.include(PwaMemberStorageQuota)
require File.join(ROOT, 'app/controllers/concerns/authentication')
require File.join(ROOT, 'app/controllers/concerns/pwa_direct_upload_access')
class Current < ActiveSupport::CurrentAttributes
  attribute :session
end
class PwaDirectUploadProbeController < ActionController::Base
  include PwaDirectUploadAccess
  def require_authentication
    user = User.find_by(id: request.headers['X-Pwa-Test-User'])
    Current.session = user && Struct.new(:user).new(user)
    head(:unauthorized) unless user
  end
  def create = render(json: {created: true})
end
Rails.application.routes.append { post '/test/direct-upload', to: 'pwa_direct_upload_probe#create' }
Rails.application.reload_routes!
class PwaMemberBoundaryTest < PwaMemberBackendTest
  PwaMemberBackendTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def test_storage_controller_boundary_requires_auth_csrf_and_source_destination
    client = ActionDispatch::Integration::Session.new(Rails.application); client.host! @site.host
    payload = {blob: {byte_size: 100}}
    client.post '/test/direct-upload', params: payload, as: :json
    assert_equal 401, client.response.status
    headers = {'X-Pwa-Test-User'=>@owner.id.to_s}
    client.post '/test/direct-upload', params: payload, headers: headers, as: :json
    assert_equal 422, client.response.status
    client.get '/test/csrf', headers: headers
    token = JSON.parse(client.response.body).fetch('csrf_token')
    client.post '/test/direct-upload', params: payload, headers: headers.merge('X-CSRF-Token'=>token), as: :json
    assert_equal 403, client.response.status
  end
  def test_central_studio_writes_cannot_bypass_member_hosting
    client = ActionDispatch::Integration::Session.new(Rails.application); client.host! @site.host
    headers = {'X-Pwa-Test-User'=>@owner.id.to_s}
    client.get '/test/csrf', headers: headers
    headers['X-CSRF-Token'] = JSON.parse(client.response.body).fetch('csrf_token')
    count = StudioProject.count
    client.post '/api/nevaeh/execute', params: {capability: 'studio.workspace.project.create', payload: {name: 'Keep off central', request_key: SecureRandom.uuid}}, headers: headers, as: :json
    assert_equal 403, client.response.status
    assert_equal count, StudioProject.count
    assert_raises(LightekPwa::Policy::Denied) do
      Studio::Workers::Workspace.perform('project_create', {'user_id'=>@owner.id, 'site_id'=>@site.id, 'name'=>'Keep off central', 'request_key'=>SecureRandom.uuid})
    end
    assert LightekPwa::Network.require_studio_write!(user: @owner, site: @site, capability: 'studio.pwa.bootstrap')
  end
  def test_shared_member_runtime_cannot_invoke_server_or_training_actions
    request = Struct.new(:path, :request_parameters) { def get? = false }
    refute LightekPwa::SourceRuntime.allowed_request?(request.new('/dashboard/servers', {}))
    refute LightekPwa::SourceRuntime.allowed_request?(request.new('/api/nevaeh/execute', {'capability'=>'nevaeh.os.execute'}))
    refute LightekPwa::SourceRuntime.allowed_request?(request.new('/api/nevaeh/execute', {'capability'=>'studio.workspace.ai.setup.install'}))
    refute LightekPwa::SourceRuntime.allowed_request?(request.new('/api/nevaeh/execute', {'capability'=>'studio.workspace.director.execute'}))
    assert LightekPwa::SourceRuntime.allowed_request?(request.new('/api/nevaeh/execute', {'capability'=>'community.post.create'}))
    assert LightekPwa::SourceRuntime.allowed_request?(request.new('/api/nevaeh/execute', {'capability'=>'studio.pwa.bootstrap'}))
  end
  def test_mounted_engine_routes_cannot_bypass_shared_backend_guard
    previous = ENV['LIGHTEK_PWA_MEMBER_BACKEND']; ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'true'
    guard = Lightek::PwaMemberGuard.new(->(_) {[200, {}, ['engine reached']]})
    assert_equal 403, guard.call(Rack::MockRequest.env_for('/dashboard/servers'))[0]
    assert_equal 200, guard.call(Rack::MockRequest.env_for('/dashboard/commerce/orders'))[0]
    assert_equal 200, guard.call(Rack::MockRequest.env_for('/'))[0]
    assert_equal 200, guard.call(Rack::MockRequest.env_for('/site/home'))[0]
    assert_equal 200, guard.call(Rack::MockRequest.env_for('/account/setup/owned-token/edit'))[0]
    assert_equal 200, guard.call(Rack::MockRequest.env_for('/api/lightek/network/posts/1'))[0]
  ensure
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = previous
  end
  def test_free_storage_quota_reserves_blob_size_before_upload
    previous_member = ENV['LIGHTEK_PWA_MEMBER_BACKEND']; previous_limit = ENV['LIGHTEK_PWA_MEMBER_STORAGE_BYTES']
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'true'
    ENV['LIGHTEK_PWA_MEMBER_STORAGE_BYTES'] = (ActiveStorage::Blob.sum(:byte_size) + 3).to_s
    count = ActiveStorage::Blob.count
    assert_raises(LightekPwa::SourceRuntime::ReadOnly) do
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new('1234'), filename: 'original.bin', content_type: 'application/octet-stream', identify: false)
    end
    assert_equal count, ActiveStorage::Blob.count
  ensure
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = previous_member
    ENV['LIGHTEK_PWA_MEMBER_STORAGE_BYTES'] = previous_limit
  end
  def test_write_freeze_applies_to_both_free_and_paid_target_runtimes
    FileUtils.mkdir_p(Rails.root.join('tmp'))
    flag = Rails.root.join('tmp/pwa-migration.lock')
    flag.write('owned-operation')
    assert LightekPwa::SourceRuntime.frozen?
    assert_raises(LightekPwa::SourceRuntime::ReadOnly) { LightekPwa::SourceRuntime.writable! }
    assert LightekPwa::SourceRuntime.control { LightekPwa::SourceRuntime.writable!; true }
  ensure
    flag&.delete if flag&.exist?
  end
end
