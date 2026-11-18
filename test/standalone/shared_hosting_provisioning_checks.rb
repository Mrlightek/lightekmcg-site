require_relative 'pwa_pool_operations_checks'
ActiveRecord::Schema.define do
  add_column :users, :first_name, :string, default: 'Member' unless column_exists?(:users, :first_name)
  add_column :users, :last_name, :string, default: 'Account' unless column_exists?(:users, :last_name)
  add_column :gatekeeper_nodes, :ip_address, :string, default: '192.0.2.10'
end
User.reset_column_information
GatekeeperNode.reset_column_information
class GatekeeperApplicationLaunch
  belongs_to :owner, class_name: 'User'
end
module Gatekeeper
  module Hosting
    class Dns
      def self.prepare!(**) = true
    end
  end
  module Fleet
    class Transport
      class RemoteFailure < StandardError; end
      def self.run!(**) = raise('Stub the SSH boundary')
    end
  end
end
module LightekVault
  class Service
    def self.checkout!(**) = {'token' => +'test-machine-credential'}
  end
end
require File.join(ROOT, 'app/services/lightek_pwa/shared_accounts')

class SharedHostingProvisioningChecks < PwaPoolOperationsTest
  PwaPoolOperationsTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def setup
    super
    @operator.update!(email_address: 'operator@example.com')
    @owner.update!(email_address: 'member@example.com')
    @pool.update!(max_members: 25)
    @base = GatekeeperApplicationLaunch.create!(gatekeeper_node: @node, owner: @operator, domain: 'members.example.com', status: 'ready', template_snapshot: {'pwa_pool' => {'profile' => 'starter'}})
    @pool.update!(launch: @base)
    @profile = {'app_root' => '/opt/lightek-sites/members.example.com/current', 'app_user' => 'lightek', 'env_file' => '/opt/lightek-sites/members.example.com/.env', 'worker_service' => 'lightek-test-sidekiq'}
    @node.update!(metadata: {'website_deployments' => {@base.domain => {'fleet_config' => @profile}}})
    @calls = []
  end
  def install(**arguments)
    @calls << arguments.deep_dup
    payload = arguments.fetch(:payload)
    {'status' => 'succeeded', 'domain' => payload[:domain], 'application_key' => payload[:application_key],
      'site_id' => @calls.length, 'shared_runtime' => payload[:runtime_domain]}
  end
  def test_two_free_customers_use_one_runtime_without_cloud_or_launch_allocation
    second = User.create!(role: 'client', email_address: 'second@example.com')
    first_backend = reserve(@owner); second_backend = reserve(second)
    before = [GatekeeperNode.count, GatekeeperApplicationLaunch.count]
    Gatekeeper::Fleet::Transport.stub(:run!, method(:install)) do
      LightekPwa::MemberBackends.provision!(first_backend)
      LightekPwa::MemberBackends.provision!(second_backend)
    end
    assert_equal before, [GatekeeperNode.count, GatekeeperApplicationLaunch.count]
    assert_nil first_backend.reload.launch_id
    assert_nil second_backend.reload.launch_id
    assert first_backend.ready?
    assert second_backend.ready?
    assert_equal %w[create_hosted_site.py create_hosted_site.py], @calls.map { |call| call[:script_name] }
    assert_equal [@base.domain], @calls.map { |call| call[:domain] }.uniq
    assert_equal [@profile], @calls.map { |call| call[:payload][:deployment] }.uniq
    refute_equal first_backend.peer.key, second_backend.peer.key
    assert_equal %w[member@example.com second@example.com], @calls.map { |call| call[:payload][:owner_email] }
    refute_includes first_backend.account_receipt.to_json, 'credential'
  end
  def test_a_wrong_account_receipt_cannot_mark_setup_ready_and_retry_reuses_the_reservation
    record = reserve(@owner)
    Gatekeeper::Fleet::Transport.stub(:run!, ->(**) { {'status' => 'succeeded', 'domain' => 'foreign.example.com'} }) do
      assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.provision!(record) }
    end
    refute record.reload.ready?
    peer = record.peer
    Gatekeeper::Fleet::Transport.stub(:run!, method(:install)) { LightekPwa::MemberBackends.provision!(record) }
    assert record.reload.ready?
    assert_equal peer.id, record.peer.id
    assert_equal 1, GatekeeperApplicationLaunch.count
    assert_nil record.launch_id
  end
  def test_operator_can_change_shared_account_limit_without_resizing_or_moving_existing_accounts
    record = reserve(@owner)
    before = [GatekeeperNode.count, GatekeeperApplicationLaunch.count, LightekPwa::SharedPool.count]
    LightekPwa::MemberBackends.set_account_limit!(site: @site, actor: @operator, pool_id: @pool.id, max_members: 50)
    assert_equal 50, @pool.reload.max_members
    assert_equal before, [GatekeeperNode.count, GatekeeperApplicationLaunch.count, LightekPwa::SharedPool.count]
    assert_equal @pool.id, record.reload.shared_pool_id
    assert_raises(LightekPwa::Policy::Denied) { LightekPwa::MemberBackends.set_account_limit!(site: @site, actor: @owner, pool_id: @pool.id, max_members: 100) }
    assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.set_account_limit!(site: @site, actor: @operator, pool_id: @pool.id, max_members: 0) }
  end
  def test_an_uncertain_account_install_never_silently_rotates_a_missing_live_credential
    record = reserve(@owner)
    Gatekeeper::Fleet::Transport.stub(:run!, ->(**) { raise Gatekeeper::Fleet::Transport::RemoteFailure }) do
      assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.provision!(record) }
    end
    assert record.reload.account_receipt['installation_started']
    digest = record.peer.token_digest
    LightekVault::Secret.records.clear
    assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.provision!(record) }
    assert_equal digest, record.peer.reload.token_digest
    assert_empty LightekVault::Secret.records
  end
  def test_migration_reuses_a_single_verified_customer_runtime_and_preserves_the_original_installation
    @pool.update!(max_members: 1)
    record = reserve(@owner)
    customer = GatekeeperApplicationLaunch.create!(gatekeeper_node: @node, owner: @owner, domain: record.hostname, status: 'ready')
    record.update!(launch: customer, hosting_mode: 'legacy_runtime', status: 'shared_ready')
    original_counts = [GatekeeperNode.count, GatekeeperApplicationLaunch.count, User.count, Post.count]
    AddSharedHostingAccounts.new.adopt_single_customer_runtimes!
    assert_equal customer.id, @pool.reload.launch_id
    assert_equal @base.id, @pool.standby_launch_id
    assert_equal 25, @pool.max_members
    assert_equal 'shared_account', record.reload.hosting_mode
    assert_equal customer.domain, record.hostname
    refute_includes Gatekeeper::Hosting::Access.site_domains(@owner), customer.domain
    assert_equal original_counts, [GatekeeperNode.count, GatekeeperApplicationLaunch.count, User.count, Post.count]
    AddSharedHostingAccounts.new.adopt_single_customer_runtimes!
    assert_equal @base.id, @pool.reload.standby_launch_id
  end
  def test_migration_never_combines_multiple_customer_databases_by_guessing
    first = reserve(@owner); second = reserve(User.create!(role: 'client'))
    [first, second].each do |record|
      launch = GatekeeperApplicationLaunch.create!(gatekeeper_node: @node, owner: record.user, domain: record.hostname, status: 'ready')
      record.update!(launch: launch, hosting_mode: 'legacy_runtime', status: 'shared_ready')
    end
    AddSharedHostingAccounts.new.adopt_single_customer_runtimes!
    assert_equal @base.id, @pool.reload.launch_id
    assert_nil @pool.standby_launch_id
    assert_equal %w[legacy_runtime legacy_runtime], [first.reload.hosting_mode, second.reload.hosting_mode]
  end
end
