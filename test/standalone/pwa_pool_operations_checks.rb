require_relative 'pwa_member_backend_checks'
require File.join(ROOT, 'db/migrate/20261117150000_add_pwa_pool_capacity_alert_state')
AddPwaPoolCapacityAlertState.new.migrate(:up)
LightekPwa::SharedPool.reset_column_information
require File.join(ROOT, 'app/models/lightek_pwa/platform_operator')
ActiveRecord::Schema.define do
  create_table(:dymond_dash_notifications) do |t|
    t.references :recipient, polymorphic: true
    t.references :subject, polymorphic: true
    t.string :category
    t.string :title
    t.text :body
    t.string :url
    t.timestamps
  end
end
module DymondDash
  class Notification < ApplicationRecord
    self.table_name = 'dymond_dash_notifications'
    belongs_to :recipient, polymorphic: true
    belongs_to :subject, polymorphic: true
  end
  class ApplicationController < ::ApplicationController; end
end
require File.join(ROOT, 'app/services/lightek_pwa/capacity_alerts')
module Dashboard; end
require File.join(ROOT, 'app/services/lightek_pwa/view_settlement')
require File.join(ROOT, 'app/controllers/dashboard/pwa_revenue_controller')
require File.join(ROOT, 'app/jobs/lightek_pwa/member_pool_job')
class PwaRevenueContextProbeController < Dashboard::PwaRevenueController
  def show = render(json: {site_id: @site.id})
end
Rails.application.routes.append do
  get '/test/revenue-context', to: 'pwa_revenue_context_probe#show'
  get '/dashboard/pwa/revenue', to: 'dashboard/pwa_revenue#show', as: :dashboard_pwa_revenue
  post '/test/pool-retry', to: 'dashboard/pwa_revenue#retry_pool'
end
Rails.application.reload_routes!
class PwaPoolOperationsTest < PwaMemberBackendTest
  PwaMemberBackendTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def setup
    super
    @purchase.destroy!
  end
  def pool(name, capacity: 3, status: 'ready', site: @site)
    node = GatekeeperNode.create!(hostname: "#{name}.test")
    LightekPwa::SharedPool.create!(site: site, operator: @operator, node: node, name: name,
      max_members: capacity, status: status, monthly_cost_ceiling_cents: 500)
  end
  def member = User.create!(role: 'client')
  def reserve(user = member) = LightekPwa::MemberBackends.reserve!(site: @site, user: user)
  def test_imported_site_revenue_context_accepts_super_admin_without_tenant_reassignment
    @site.update!(tenant: @owner)
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.host! @site.host
    client.get '/test/revenue-context', params: {site_id: @site.id}, headers: {'X-Pwa-Test-User' => @operator.id.to_s}
    assert_equal 200, client.response.status, client.response.body
    assert_equal @site.id, JSON.parse(client.response.body)['site_id']
    assert_equal @owner, @site.reload.tenant
    client.get '/test/revenue-context', params: {site_id: @site.id}, headers: {'X-Pwa-Test-User' => @owner.id.to_s}
    assert_equal 403, client.response.status
  end
  def pool_retry_request(pool, actor: @operator)
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.host! @site.host
    headers = {'X-Pwa-Test-User' => actor.id.to_s, 'Accept' => 'application/json'}
    client.get '/test/csrf', headers: headers
    token = JSON.parse(client.response.body).fetch('csrf_token')
    client.post '/test/pool-retry', params: {site_id: @site.id, pool_id: pool.id}, headers: headers.merge('X-CSRF-Token'=>token)
    client
  end
  def test_pool_retry_queues_the_existing_pool_without_creating_another_node_or_pool
    @pool.update!(status: 'provisioning')
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
    jobs.clear
    before = [LightekPwa::SharedPool.count, GatekeeperNode.count]
    client = pool_retry_request(@pool)
    assert_equal 302, client.response.status, client.response.body
    assert_equal before, [LightekPwa::SharedPool.count, GatekeeperNode.count]
    assert_equal 1, jobs.length
    assert_equal LightekPwa::MemberPoolJob, jobs.last.fetch(:job)
    assert_equal [@pool.id], jobs.last.fetch(:args)
  end
  def test_pool_retry_rejects_foreign_pools_and_ordinary_users
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
    jobs.clear
    foreign = pool('foreign-retry', site: @remote, status: 'provisioning')
    assert_equal 404, pool_retry_request(foreign).response.status
    assert_equal 403, pool_retry_request(@pool, actor: @owner).response.status
    assert_empty jobs
  end
  def test_platform_binding_is_explicit_and_super_admin_only
    @site.update!(tenant: @owner)
    @site.update!(manifest: {'pwa_platform_operator_id' => @operator.id})
    assert_nil LightekPwa::Policy.platform_operator(@site), 'Public manifest content cannot claim platform credentials'
    assert_raises(LightekPwa::Policy::Denied) { LightekPwa::Policy.bind_platform!(site: @site, actor: @owner) }
    LightekPwa::Policy.bind_platform!(site: @site, actor: @operator)
    assert_equal @operator, LightekPwa::Policy.platform_operator(@site.reload)
    assert_equal @owner, @site.tenant
    assert LightekPwa::Network.write_destination(user: @owner, site: @site)[:member_backend]
    @operator.update!(role: 'client')
    assert_nil LightekPwa::Policy.platform_operator(@site)
  end
  def test_smallest_live_plan_includes_one_gb_and_rejects_zero_prices_and_insufficient_disk
    plans = [
      {'id'=>'zero', 'memory'=>1024, 'disk'=>25600, 'monthly_cents'=>0},
      {'id'=>'tiny-disk', 'memory'=>1024, 'disk'=>8000, 'monthly_cents'=>100},
      {'id'=>'nanode-1', 'memory'=>1024, 'disk'=>25600, 'monthly_cents'=>500},
      {'id'=>'linode-2', 'memory'=>2048, 'disk'=>51200, 'monthly_cents'=>1200},
      {'id'=>'linode-4', 'memory'=>4096, 'disk'=>81920, 'monthly_cents'=>2400}]
    assert_equal 'nanode-1', LightekPwa::MemberBackends.smallest_plan!(plans)['id']
    assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.smallest_plan!(plans.take(2)) }
    LightekPwa::MemberBackends.stub(:smallest_offer!, {plan: plans[3], capacity: 1}) do
      assert_raises(LightekPwa::MemberBackends::Unavailable) do
        LightekPwa::MemberBackends.create_smallest_pool!(site: @site, actor: @operator, region: 'us-mia', plan_id: 'nanode-1', monthly_cents: 500, request_key: SecureRandom.uuid)
      end
    end
  end
  def test_default_server_switch_affects_only_new_members
    second = pool('second')
    LightekPwa::MemberBackends.configure_routing!(site: @site, actor: @operator, mode: 'default', default_pool_id: @pool.id)
    existing = reserve
    LightekPwa::MemberBackends.configure_routing!(site: @site, actor: @operator, mode: 'default', default_pool_id: second.id)
    assert_equal second, reserve.shared_pool
    assert_equal @pool, existing.reload.shared_pool
    assert_equal existing, reserve(existing.user)
  end
  def test_round_robin_skips_full_paused_and_central_servers_and_wraps
    @pool.update!(max_members: 2)
    second = pool('second', capacity: 2)
    paused = pool('paused', status: 'paused')
    unsafe = pool('central'); unsafe.node.update!(local: true)
    LightekPwa::MemberBackends.configure_routing!(site: @site, actor: @operator, mode: 'round_robin')
    assert_equal [@pool.id, second.id, @pool.id, second.id], 4.times.map { reserve.shared_pool_id }
    assert_raises(LightekPwa::MemberBackends::Unavailable) { reserve }
    assert_equal 0, paused.member_backends.count
    assert_equal 0, unsafe.member_backends.count
    assert_equal second.id, @site.reload.manifest.dig('pwa_pool_routing', 'last_pool_id')
  end
  def test_routing_rejects_foreign_pool_and_ordinary_member_changes
    foreign = pool('foreign', site: @remote)
    assert_raises(ActiveRecord::RecordNotFound) { LightekPwa::MemberBackends.configure_routing!(site: @site, actor: @operator, mode: 'default', default_pool_id: foreign.id) }
    assert_raises(LightekPwa::Policy::Denied) { LightekPwa::MemberBackends.configure_routing!(site: @site, actor: @owner, mode: 'round_robin') }
    assert_raises(LightekPwa::MemberBackends::Unavailable) { LightekPwa::MemberBackends.configure_routing!(site: @site, actor: @operator, mode: 'random') }
  end
  def test_full_default_queues_without_falling_back_to_another_server
    other = pool('other')
    LightekPwa::MemberBackends.configure_routing!(site: @site, actor: @operator, mode: 'default', default_pool_id: @pool.id)
    reserve
    assert_raises(LightekPwa::MemberBackends::Unavailable) { reserve }
    assert_empty other.member_backends
  end
  def test_capacity_notifications_are_durable_deduplicated_and_escalate_then_reset
    @pool.update!(max_members: 4)
    2.times { reserve }
    LightekPwa::CapacityAlerts.call!(@pool)
    assert_equal 0, DymondDash::Notification.count
    reserve
    2.times { LightekPwa::CapacityAlerts.call!(@pool) }
    assert_equal 1, DymondDash::Notification.count
    notice = DymondDash::Notification.sole
    assert_equal @operator, notice.recipient
    assert_equal @pool, notice.subject
    assert_includes notice.body, '1 remaining'
    reserve
    2.times { LightekPwa::CapacityAlerts.call!(@pool) }
    assert_equal 2, DymondDash::Notification.count
    assert_equal 'Free-member server is full', DymondDash::Notification.last.title
    @pool.update!(max_members: 8)
    LightekPwa::CapacityAlerts.call!(@pool)
    assert_equal 'normal', @pool.reload.capacity_alert_state
    3.times { reserve }
    LightekPwa::CapacityAlerts.call!(@pool)
    assert_equal 3, DymondDash::Notification.count
  end
  def test_pause_resume_changes_only_new_placement_and_preserves_existing_backends
    existing = reserve
    @pool.update!(launch: GatekeeperApplicationLaunch.create!(gatekeeper_node: @node, status: 'ready'))
    LightekPwa::MemberBackends.set_pool_status!(site: @site, actor: @operator, pool_id: @pool.id, status: 'paused')
    assert_equal 'paused', @pool.reload.status
    assert_equal existing, reserve(existing.user)
    assert_raises(LightekPwa::MemberBackends::Unavailable) { reserve }
    LightekPwa::MemberBackends.set_pool_status!(site: @site, actor: @operator, pool_id: @pool.id, status: 'ready')
    assert_equal 'ready', @pool.reload.status
    assert_raises(LightekPwa::Policy::Denied) { LightekPwa::MemberBackends.set_pool_status!(site: @site, actor: @owner, pool_id: @pool.id, status: 'paused') }
  end
  def test_starter_view_exposes_live_price_new_pool_and_placement_controls
    view = ActionView::Base.with_empty_template_cache.with_view_paths(File.join(ROOT, 'app/views'))
    view.assign(site: @site, shared_pools: [@pool], member_backends: [], pool_packages: [], view_batches: [],
      launch_readiness: {launch_candidate: false, paid_sales_ready: false, implementation_gaps: {}, configuration: {}, production_acceptance: {}},
      starter_offer: {plan: {'id'=>'nanode-1','label'=>'Nanode 1GB','monthly_cents'=>500}, region: 'us-mia', capacity: 1},
      membership: {enabled: false, setup_note: 'Preparing'}, packages: [], purchases: [], youtube_uploads: [], creator_earnings: [], receipts: [], learning_build: nil)
    %i[retry_pool_dashboard_pwa_revenue_path dashboard_pwa_path smallest_pool_dashboard_pwa_revenue_path routing_dashboard_pwa_revenue_path status_dashboard_pwa_revenue_pool_path pools_dashboard_pwa_revenue_path finalize_views_dashboard_pwa_revenue_path import_dashboard_pwa_revenue_path prepare_nevaeh_dashboard_pwa_revenue_path].each { |name| view.define_singleton_method(name) { |**| '/dashboard/pwa/revenue' } }
    view.define_singleton_method(:flash) { {} }
    view.define_singleton_method(:protect_against_forgery?) { false }
    html = view.render(template: 'dashboard/pwa_revenue/show')
    assert_includes html, 'Nanode 1GB'
    assert_includes html, '$5.00/month'
    assert_includes html, 'Add another smallest shared server'
    assert_includes html, 'Round robin across ready servers'
    assert_includes html, 'Save free-member placement'
    assert_includes html, 'Pause new placements on'
  end
  def test_small_starter_notifies_at_first_full_reservation_and_failed_delivery_retries
    reserve
    DymondDash::Notification.stub(:create!, ->(**) { raise 'notification unavailable' }) do
      assert_raises(RuntimeError) { LightekPwa::CapacityAlerts.call!(@pool) }
    end
    assert_equal 'normal', @pool.reload.capacity_alert_state
    LightekPwa::CapacityAlerts.call!(@pool)
    assert_equal 'full', @pool.reload.capacity_alert_state
    assert_equal 1, DymondDash::Notification.count
  end
end
