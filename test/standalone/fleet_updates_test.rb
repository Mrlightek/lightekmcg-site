# frozen_string_literal: true
# Isolated persistence tests for the actual fleet models/services; no ecosystem gems.
# ruby test/standalone/fleet_updates_test.rb
gem "minitest", "~> 5.0"
require "minitest/autorun"
require "minitest/mock"
require "active_record"
require "active_job"
require "active_support/all"
require "logger"
require "pathname"
require "active_support/testing/time_helpers"

module Rails
  def self.root = Pathname.new(File.expand_path("../..", __dir__))
  def self.logger = Logger.new(File::NULL)
end
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
class ApplicationJob < ActiveJob::Base; end
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(File::NULL)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false
# SQLite exercises the real uniqueness/partial-index/transaction semantics. The
# production migration uses JSONB on PostgreSQL; SQLite uses JSON for these tests.
ActiveRecord::ConnectionAdapters::TableDefinition.class_eval { alias_method :jsonb, :json }
ActiveRecord::Schema.define do
  create_table(:gatekeeper_nodes) do |t|
    t.string :name; t.string :hostname; t.string :ip_address; t.string :ssh_user
    t.integer :ssh_port, default: 22; t.string :ssh_key_path; t.string :status, default: "healthy"
    t.json :metadata, default: {}; t.timestamps
    t.string :owner_type; t.integer :owner_id
    t.references :compute_provider; t.string :provider_resource_id
  end
  create_table(:gatekeeper_operations) do |t|
    t.references :gatekeeper_node; t.references :gatekeeper_project
    t.string :capability; t.string :requested_by; t.string :status
    t.json :parameters, default: {}; t.json :result, default: {}
    t.integer :exit_status; t.string :error_class; t.string :error_message
    t.datetime :started_at; t.datetime :completed_at; t.timestamps
  end
  create_table(:users) { |t| t.string :email_address; t.string :role, default: "client" }
  create_table(:compute_providers) { |t| t.string :name; t.string :slug }
  create_table(:subscription_infrastructure_entitlements) do |t|
    t.integer :subscription_plan_id; t.integer :node_quantity, default: 1
  end
  create_table(:dymond_bank_subscriptions) do |t|
    t.references :subscriber, polymorphic: true; t.integer :plan_id; t.string :status
    t.datetime :current_period_start; t.datetime :current_period_end; t.datetime :trial_ends_at
  end
  create_table(:provisioning_requests) do |t|
    t.references :owner, polymorphic: true; t.references :gatekeeper_node; t.references :compute_provider
    t.string :approval_status; t.string :execution_status; t.integer :requested_node_count
    t.string :destroy_approval_status; t.string :destroy_approved_by; t.datetime :destroy_approved_at
    t.datetime :destroyed_at; t.json :metadata, default: {}
  end
  create_table(:gatekeeper_projects) do |t|
    t.string :name; t.string :deployed_sha; t.references :gatekeeper_node
    t.string :domain; t.string :repository; t.string :app_root; t.string :app_user
    t.string :ruby_version, default: "3.3.6"; t.json :metadata, default: {}
    t.string :status; t.datetime :last_deployed_at; t.datetime :last_healthcheck_at
  end
end
class User < ApplicationRecord; end
class ComputeProvider < ApplicationRecord
  class_attribute :test_adapter
  def adapter(**) = self.class.test_adapter
end
class ProvisioningRequest < ApplicationRecord
  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :gatekeeper_node
  belongs_to :compute_provider
end
class SubscriptionInfrastructureEntitlement < ApplicationRecord; end
module DymondBank
  class Subscription < ApplicationRecord
    self.table_name = "dymond_bank_subscriptions"
    belongs_to :subscriber, polymorphic: true
  end
end
class GatekeeperProject < ApplicationRecord
  def sidekiq_service = "#{name}-sidekiq"
  def health_url = "https://#{domain}/up"
end
source = File.read(Rails.root.join("db/migrate/20261031210000_create_gatekeeper_fleet_updates.rb"))
eval(source.sub("Migration[8.0]", "Migration[7.2]"), TOPLEVEL_BINDING, "fleet_migration")
CreateGatekeeperFleetUpdates.new.migrate(:up)
source = File.read(Rails.root.join("db/migrate/20261031220000_add_native_fleet_adapters.rb"))
eval(source.sub("Migration[8.0]", "Migration[7.2]"), TOPLEVEL_BINDING, "native_fleet_migration")
AddNativeFleetAdapters.new.migrate(:up)
source = File.read(Rails.root.join("db/migrate/20261031230000_add_server_application_management.rb"))
eval(source.sub("Migration[8.0]", "Migration[7.2]"), TOPLEVEL_BINDING, "hosting_migration")
AddServerApplicationManagement.new.migrate(:up)
require Rails.root.join("app/services/gatekeeper/fleet/adapters").to_s
%w[gatekeeper_node gatekeeper_operation gatekeeper_installation gatekeeper_release gatekeeper_rollout gatekeeper_update_target].each do |file|
  require Rails.root.join("app/models", file).to_s
end
%w[rollouts releases inventory transport update].each { |file| require Rails.root.join("app/services/gatekeeper/fleet", file).to_s }
%w[dispatch_job update_job sweep_job].each { |file| require Rails.root.join("app/jobs/gatekeeper/fleet", file).to_s }
module Gatekeeper::KnowledgeService
  def self.find_for_failure(**) = []
end
module Gatekeeper::SupportTicketService
  def self.open_for_failure!(**) = Struct.new(:id, :number).new(1, "TEST-1")
end

class FleetUpdatesTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers
  def setup
    GatekeeperUpdateTarget.delete_all; GatekeeperRollout.delete_all
    GatekeeperHostedApplication.delete_all if defined?(GatekeeperHostedApplication)
    ProvisioningRequest.delete_all; DymondBank::Subscription.delete_all; SubscriptionInfrastructureEntitlement.delete_all
    GatekeeperInstallation.update_all(pinned_release_id: nil)
    GatekeeperRelease.delete_all
    GatekeeperInstallation.delete_all; GatekeeperOperation.delete_all; GatekeeperNode.delete_all
    GatekeeperProject.delete_all; User.delete_all; ComputeProvider.delete_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    @release = release
    @old_auto = ENV.delete("LIGHTEK_FLEET_AUTO_ROLLOUT")
    @old_promote = ENV.delete("LIGHTEK_FLEET_AUTO_PROMOTE")
  end

  def teardown
    ENV["LIGHTEK_FLEET_AUTO_ROLLOUT"] = @old_auto
    ENV["LIGHTEK_FLEET_AUTO_PROMOTE"] = @old_promote
  end

  def release(version = SecureRandom.hex(4), **options)
    GatekeeperRelease.create!({version: version, source_sha: "a" * 40,
      adapter: "docker_compose",
      image: "ghcr.io/mrlightek/lightekmcg-site/customer@sha256:#{'b' * 64}",
      created_by: "operator"}.merge(options))
  end

  def installation(index = SecureRandom.hex(4), **options)
    node = GatekeeperNode.create!(name: "node-#{index}", ip_address: "203.0.113.10", ssh_user: "root")
    GatekeeperInstallation.create!({domain: "client-#{index}.example.com", gatekeeper_node: node,
      adapter: "docker_compose",
      current_version: "previous", current_image: "previous-image"}.merge(options))
  end

  def rollout(count = 3, **options)
    Gatekeeper::Fleet::Rollouts.create!(release: @release,
      installations: Array.new(count) { installation }, requested_by: "operator", **options)
  end

  def succeeded(target)
    record = target.gatekeeper_rollout.gatekeeper_release
    {"status" => "succeeded", "domain" => target.gatekeeper_installation.domain,
      "source_sha" => record.source_sha, "image" => record.image, "database_backup" => "/safe/backup.sql"}
      .merge("adapter" => record.adapter, "component" => record.component)
  end

  def dispatch(record)
    Gatekeeper::Fleet::DispatchJob.new.perform(record.id)
    record.reload
  end

  def run_targets(record)
    Gatekeeper::Fleet::Transport.stub(:call!, ->(target) { succeeded(target) }) do
      record.gatekeeper_update_targets.where(status: "queued").each { |target| Gatekeeper::Fleet::Update.call!(target) }
    end
  end

  def test_only_persisted_super_admin_can_control_fleet
    actor = Struct.new(:role) { def persisted? = true }
    [nil, actor.new("client"), actor.new("admin")].each do |user|
      assert_raises(Gatekeeper::Fleet::Rollouts::Invalid) { Gatekeeper::Fleet::Rollouts.authorize!(user) }
    end
    Gatekeeper::Fleet::Rollouts.authorize!(actor.new("super_admin"))
  end

  def callback_payload(version = SecureRandom.hex(4))
    {"version" => version, "source_sha" => "a" * 40, "image" => @release.image, "adapter" => "docker_compose", "notes" => "Test release"}
  end

  def test_callback_replay_is_idempotent_and_cannot_replace_a_digest
    payload = callback_payload
    first = Gatekeeper::Fleet::Releases.register!(payload)
    assert_equal first.id, Gatekeeper::Fleet::Releases.register!(payload).id
    assert_raises(Gatekeeper::Fleet::Rollouts::Invalid) do
      Gatekeeper::Fleet::Releases.register!(payload.merge("image" => "ghcr.io/test/image@sha256:#{'c' * 64}"))
    end
    assert_equal @release.image, first.reload.image
  end

  def test_automatic_releases_require_explicit_opt_in_and_current_production_revision
    ENV["LIGHTEK_FLEET_AUTO_ROLLOUT"] = "true"
    installation(automatic_updates: true)
    installation(automatic_updates: false)
    project = GatekeeperProject.create!(name: "lightekmcg-site", deployed_sha: "c" * 40)
    old = Gatekeeper::Fleet::Releases.register!(callback_payload)
    assert_equal 0, old.gatekeeper_rollouts.count
    project.update!(deployed_sha: "a" * 40)
    payload = callback_payload
    current = Gatekeeper::Fleet::Releases.register!(payload)
    assert_equal 1, current.gatekeeper_rollouts.count
    record = current.gatekeeper_rollouts.first
    assert_equal "running", record.status
    assert_equal 1, record.gatekeeper_update_targets.count
    Gatekeeper::Fleet::Releases.register!(payload)
    assert_equal 1, current.gatekeeper_rollouts.count
  end

  def test_new_automatic_release_waits_for_active_rollout_and_stale_draft_is_canceled
    ENV["LIGHTEK_FLEET_AUTO_ROLLOUT"] = "true"
    installation(automatic_updates: true)
    project = GatekeeperProject.create!(name: "lightekmcg-site", deployed_sha: "a" * 40)
    first = Gatekeeper::Fleet::Releases.register!(callback_payload).gatekeeper_rollouts.first
    next_release = Gatekeeper::Fleet::Releases.register!(callback_payload)
    waiting = next_release.gatekeeper_rollouts.first
    assert_equal "draft", waiting.status
    Gatekeeper::Fleet::Rollouts.control!(first, "cancel")
    Gatekeeper::Fleet::SweepJob.new.perform
    assert_equal "running", waiting.reload.status
    newer = Gatekeeper::Fleet::Releases.register!(callback_payload).gatekeeper_rollouts.first
    project.update!(deployed_sha: "d" * 40)
    Gatekeeper::Fleet::SweepJob.new.perform
    assert_equal "canceled", newer.reload.status
  end

  def test_releases_require_full_sha_digest_and_are_immutable
    ["ghcr.io/example/customer:latest", "http://example.test/image", "ghcr.io/example/customer@sha256:bad"].each do |image|
      refute GatekeeperRelease.new(@release.attributes.except("id").merge("version" => SecureRandom.hex(4), "image" => image)).valid?
    end
    assert_raises(ActiveRecord::ReadonlyAttributeError) { @release.update!(image: "changed") } if ActiveRecord.raise_on_assign_to_attr_readonly
    unless ActiveRecord.raise_on_assign_to_attr_readonly
      @release.update!(image: "ghcr.io/test/image@sha256:#{'c' * 64}")
      assert_match(/#{'b' * 64}/, @release.reload.image)
    end
  end

  def test_canary_requires_explicit_promotion_and_batches_are_bounded
    record = rollout(6, canary_size: 1, batch_size: 2)
    Gatekeeper::Fleet::Rollouts.start!(record)
    dispatch(record)
    assert_equal 1, record.gatekeeper_update_targets.where(status: "queued").count
    run_targets(record); dispatch(record)
    assert_equal "canary_ready", record.status
    assert_equal 5, record.gatekeeper_update_targets.where(status: "reserved").count
    Gatekeeper::Fleet::Rollouts.control!(record, "resume")
    dispatch(record)
    assert_equal 2, record.gatekeeper_update_targets.where(status: "queued").count
    3.times { run_targets(record); dispatch(record) }
    assert_equal "completed", record.status
    assert_equal 6, record.gatekeeper_update_targets.where(status: "succeeded").count
    assert_equal 6, GatekeeperOperation.where(status: "succeeded").count
  end

  def test_thousand_customer_snapshot_queues_only_configured_batch
    record = rollout(1000, batch_size: 20, auto_promote: true)
    Gatekeeper::Fleet::Rollouts.start!(record); dispatch(record); run_targets(record); dispatch(record)
    assert_equal 20, record.gatekeeper_update_targets.where(status: "queued").count
    assert_equal 979, record.gatekeeper_update_targets.where(status: "reserved").count
  end

  def test_duplicate_jobs_do_not_repeat_a_successful_update
    record = rollout(1)
    Gatekeeper::Fleet::Rollouts.start!(record); dispatch(record)
    calls = 0
    Gatekeeper::Fleet::Transport.stub(:call!, ->(target) { calls += 1; succeeded(target) }) do
      target = record.gatekeeper_update_targets.first
      3.times { Gatekeeper::Fleet::Update.call!(target) }
    end
    assert_equal 1, calls
    assert_equal 1, GatekeeperOperation.count
  end

  def test_failure_pauses_and_retry_preserves_successes
    record = rollout(3, canary_size: 2, batch_size: 2)
    Gatekeeper::Fleet::Rollouts.start!(record); dispatch(record)
    first, second = record.gatekeeper_update_targets.where(status: "queued").order(:id).to_a
    Gatekeeper::Fleet::Transport.stub(:call!, ->(target) { succeeded(target) }) { Gatekeeper::Fleet::Update.call!(first) }
    Gatekeeper::Fleet::Transport.stub(:call!, ->(_) { raise "secret-do-not-store" }) { Gatekeeper::Fleet::Update.call!(second) }
    assert_equal "paused", record.reload.status
    assert_equal "failed", second.reload.status
    refute_includes second.error_message, "secret-do-not-store"
    assert_raises(Gatekeeper::Fleet::Rollouts::Invalid) { Gatekeeper::Fleet::Rollouts.control!(record, "resume") }
    Gatekeeper::Fleet::Rollouts.control!(record, "retry"); dispatch(record); run_targets(record); dispatch(record)
    assert_equal 1, first.reload.attempts
    assert_equal 2, second.reload.attempts
    assert_equal "canary_ready", record.status
  end

  def test_wrong_remote_revision_does_not_mark_customer_updated
    record = rollout(1)
    Gatekeeper::Fleet::Rollouts.start!(record); dispatch(record)
    target = record.gatekeeper_update_targets.first
    Gatekeeper::Fleet::Transport.stub(:call!, ->(t) { succeeded(t).merge("source_sha" => "wrong") }) { Gatekeeper::Fleet::Update.call!(target) }
    assert_equal "failed", target.reload.status
    assert_equal "previous", target.gatekeeper_installation.reload.current_version
  end

  def test_failed_remote_receipt_preserves_recovery_evidence
    record = rollout(1)
    Gatekeeper::Fleet::Rollouts.start!(record); dispatch(record)
    target = record.gatekeeper_update_targets.first
    evidence = {"status" => "failed", "database_backup" => "/safe/backup.sql", "code_restored" => true,
      "migration_started" => true, "password" => "never-persist-this"}
    Gatekeeper::Fleet::Transport.stub(:call!, ->(_) { raise Gatekeeper::Fleet::Transport::RemoteFailure.new(evidence) }) do
      Gatekeeper::Fleet::Update.call!(target)
    end
    assert_equal "/safe/backup.sql", target.reload.receipt["database_backup"]
    assert target.receipt["code_restored"]
    refute_includes target.receipt.to_json, "never-persist-this"
    assert_equal 1, target.gatekeeper_operation.result["support_ticket_id"]
  end

  def test_overlapping_rollouts_cannot_reserve_same_installation
    customer = installation
    a, b = 2.times.map { Gatekeeper::Fleet::Rollouts.create!(release: @release, installations: [customer], requested_by: "operator") }
    Gatekeeper::Fleet::Rollouts.start!(a)
    assert_raises(Gatekeeper::Fleet::Rollouts::Invalid) { Gatekeeper::Fleet::Rollouts.start!(b) }
    assert_equal "draft", b.reload.status
    Gatekeeper::Fleet::Rollouts.control!(a, "cancel")
    Gatekeeper::Fleet::Rollouts.start!(b)
    assert_equal "running", b.reload.status
  end

  def test_pause_blocks_queued_jobs_until_resume_and_cancel_releases_reservations
    record = rollout(3)
    Gatekeeper::Fleet::Rollouts.start!(record); dispatch(record)
    Gatekeeper::Fleet::Rollouts.control!(record, "pause")
    Gatekeeper::Fleet::Transport.stub(:call!, ->(_) { flunk "paused rollout executed" }) do
      Gatekeeper::Fleet::Update.call!(record.gatekeeper_update_targets.first)
    end
    assert_equal 0, GatekeeperOperation.count
    Gatekeeper::Fleet::Rollouts.control!(record, "cancel")
    assert_equal 3, record.gatekeeper_update_targets.where(status: "canceled").count
  end

  def test_scheduled_rollout_waits_until_due
    record = rollout(2, scheduled_at: 1.hour.from_now)
    Gatekeeper::Fleet::Rollouts.start!(record); dispatch(record)
    assert_equal 0, record.gatekeeper_update_targets.where(status: "queued").count
    travel 2.hours do
      dispatch(record)
    end
    assert_equal 1, record.gatekeeper_update_targets.where(status: "queued").count
  end

  def test_recovery_requeues_lost_enqueue_and_pauses_stale_workers
    record = rollout(2)
    Gatekeeper::Fleet::Rollouts.start!(record)
    Gatekeeper::Fleet::Rollouts.dispatch!(record)
    target = record.gatekeeper_update_targets.find_by!(status: "queued")
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    dispatch(record)
    assert ActiveJob::Base.queue_adapter.enqueued_jobs.any? { |job| job[:job] == Gatekeeper::Fleet::UpdateJob }
    target.update!(status: "running", started_at: 2.hours.ago)
    Gatekeeper::Fleet::SweepJob.new.perform
    assert_equal "paused", record.reload.status
    assert_equal "failed", target.reload.status
  end

  def test_inventory_is_idempotent_preserves_policy_and_excludes_control_plane
    node = installation.gatekeeper_node
    node.update!(metadata: {"website_deployments" => {"registered.example.com" => {}},
      "website_deployment" => {"url" => "https://registered.example.com", "release" => "old-release"}})
    2.times { Gatekeeper::Fleet::Inventory.sync_node!(node) }
    item = GatekeeperInstallation.find_by!(domain: "registered.example.com")
    item.update!(enabled: false, channel: "beta")
    Gatekeeper::Fleet::Inventory.sync_node!(node)
    refute item.reload.enabled?
    assert_equal "beta", item.channel
    assert_equal "old-release", item.current_version
    node.update!(metadata: {"role" => "production", "website_deployments" => {"central.example.com" => {}}})
    Gatekeeper::Fleet::Inventory.sync_node!(node)
    refute GatekeeperInstallation.exists?(domain: "central.example.com")
  end

  def test_disabled_decommissioned_or_wrong_channel_customers_are_refused
    [installation(enabled: false), installation(channel: "beta")].each do |item|
      assert_raises(Gatekeeper::Fleet::Rollouts::Invalid) do
        Gatekeeper::Fleet::Rollouts.create!(release: @release, installations: [item], requested_by: "operator")
      end
    end
    item = installation
    record = Gatekeeper::Fleet::Rollouts.create!(release: @release, installations: [item], requested_by: "operator")
    item.gatekeeper_node.update!(status: "decommissioned")
    assert_raises(Gatekeeper::Fleet::Rollouts::Invalid) { Gatekeeper::Fleet::Rollouts.start!(record) }
    assert_equal "draft", record.reload.status
  end

  def native_profile
    {"app_root" => "/var/www/customer", "app_user" => "lightek", "env_file" => "/etc/lightek/customer.env",
      "ruby_bin" => "/home/lightek/.rbenv/versions/3.3.6/bin", "worker_mode" => "systemd", "worker_service" => "customer-sidekiq",
      "health_url" => "https://customer.example.com/up", "revision_url" => "https://customer.example.com/__lightek/release"}
  end

  def test_native_release_does_not_require_application_image_and_dispatches_host_adapter
    native = release(adapter: "native_rails", image: nil)
    item = installation(adapter: "native_rails", domain: "customer.example.com", deployment_config: native_profile)
    assert item.accepts_release?(native)
    payload = Gatekeeper::Fleet::Adapters.payload(item, native)
    assert_equal "native_rails", payload[:adapter]
    assert_equal "/var/www/customer", payload[:deployment]["app_root"]
    assert_equal "update_native_installation.py", Gatekeeper::Fleet::Adapters.script(item.adapter)
    record = Gatekeeper::Fleet::Rollouts.create!(release: native, installations: [item], requested_by: "operator")
    Gatekeeper::Fleet::Rollouts.start!(record); dispatch(record); run_targets(record)
    assert_equal "succeeded", record.gatekeeper_update_targets.first.status
    assert_nil item.reload.current_image
  end

  def test_custom_pin_blocks_manual_and_automatic_general_releases
    custom = release
    customer = installation(automatic_updates: true, pinned_release: custom)
    assert customer.accepts_release?(custom)
    refute customer.accepts_release?(@release)
    assert_raises(Gatekeeper::Fleet::Rollouts::Invalid) do
      Gatekeeper::Fleet::Rollouts.create!(release: @release, installations: [customer], requested_by: "operator")
    end
    ENV["LIGHTEK_FLEET_AUTO_ROLLOUT"] = "true"
    GatekeeperProject.create!(name: "lightekmcg-site", deployed_sha: "a" * 40)
    latest = Gatekeeper::Fleet::Releases.register!(callback_payload)
    assert_empty latest.gatekeeper_rollouts
  end

  def test_adapter_component_and_repository_are_independent_release_boundaries
    item = installation
    [release(adapter: "native_rails", image: nil), release(component: "cdn"),
      release(repository: "https://github.com/example/custom.git")].each do |wrong|
      refute item.accepts_release?(wrong)
    end
    item.update!(repository: "git@github.com:Mrlightek/lightekmcg-site.git")
    assert item.accepts_release?(@release)
    item.pinned_release = release(component: "cdn")
    refute item.valid?
  end

  def test_native_project_inventory_uses_passenger_checkout_and_preserves_saved_profile
    node = installation.gatekeeper_node
    account = User.create!(email_address: "customer@example.com")
    node.update!(owner_type: "User", owner_id: account.id)
    project = GatekeeperProject.create!(name: "customer", gatekeeper_node_id: node.id, domain: "native.example.com",
      app_root: "/var/www/native", app_user: "lightek", repository: Gatekeeper::Fleet::Adapters::MAIN_REPOSITORY,
      deployed_sha: "a" * 40, metadata: {})
    Gatekeeper::Fleet::Inventory.sync_node!(node)
    item = GatekeeperInstallation.find_by!(domain: project.domain)
    assert_equal "native_rails", item.adapter
    assert_equal "/var/www/native", item.deployment_config["app_root"]
    assert_equal account.id, item.account_id
    item.update!(deployment_config: item.deployment_config.merge("worker_mode" => "none"))
    Gatekeeper::Fleet::Inventory.sync_node!(node)
    assert_equal "none", item.reload.deployment_config["worker_mode"]
  end

  def test_specialized_services_can_share_hostname_without_sharing_release_component
    a = installation(domain: "service.example.com")
    b = installation(domain: "service.example.com", adapter: "systemd_service", component: "realtime",
      deployment_config: {"app_root" => "/opt/realtime", "app_user" => "lightek", "service_name" => "realtime",
        "health_url" => "https://service.example.com/health", "verify_hook" => "/opt/realtime/bin/verify"})
    refute_equal a.id, b.id
    record = release(adapter: "systemd_service", image: nil, component: "realtime")
    assert b.accepts_release?(record)
    refute a.accepts_release?(record)
  end

  def test_deployment_profiles_reject_shell_injection_unknown_fields_and_embedded_secrets
    [native_profile.merge("worker_service" => "sidekiq; reboot"), native_profile.merge("app_root" => "/var/www/../etc"),
      native_profile.merge("health_url" => "https://user:password@customer.example.com/up"),
      native_profile.merge("command" => "rm -rf /"), native_profile.merge("app_user" => "user\nroot")].each do |config|
      assert_raises(ArgumentError) { Gatekeeper::Fleet::Adapters.validate!("native_rails", config) }
    end
    unknown = installation(adapter: "native_rails", deployment_config: {})
    refute unknown.eligible?
  end

  def test_specialized_component_on_production_node_does_not_require_updating_main_app
    item = installation(component: "cdn")
    item.gatekeeper_node.update!(metadata: {"role" => "production", "local_node" => true})
    assert item.eligible?
    item.component = "lightek_app"
    refute item.eligible?
  end

  def test_cdn_replicas_can_share_public_hostname_and_component_on_different_nodes
    a = installation(domain: "cdn.example.com", component: "cdn")
    b = installation(domain: "cdn.example.com", component: "cdn")
    refute_equal a.gatekeeper_node_id, b.gatekeeper_node_id
    assert_equal 2, GatekeeperInstallation.where(domain: "cdn.example.com", component: "cdn").count
  end
end

require_relative "fleet_hosting_test"
require_relative "fleet_transport_test"
