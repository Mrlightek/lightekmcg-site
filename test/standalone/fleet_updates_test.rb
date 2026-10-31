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
  end
  create_table(:gatekeeper_operations) do |t|
    t.references :gatekeeper_node; t.references :gatekeeper_project
    t.string :capability; t.string :requested_by; t.string :status
    t.json :parameters, default: {}; t.json :result, default: {}
    t.integer :exit_status; t.string :error_class; t.string :error_message
    t.datetime :started_at; t.datetime :completed_at; t.timestamps
  end
  create_table(:gatekeeper_projects) { |t| t.string :name; t.string :deployed_sha }
end
class GatekeeperProject < ApplicationRecord; end
source = File.read(Rails.root.join("db/migrate/20261031210000_create_gatekeeper_fleet_updates.rb"))
eval(source.sub("Migration[8.0]", "Migration[7.2]"), TOPLEVEL_BINDING, "fleet_migration")
CreateGatekeeperFleetUpdates.new.migrate(:up)
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
    GatekeeperUpdateTarget.delete_all; GatekeeperRollout.delete_all; GatekeeperRelease.delete_all
    GatekeeperInstallation.delete_all; GatekeeperOperation.delete_all; GatekeeperNode.delete_all
    GatekeeperProject.delete_all
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
      image: "ghcr.io/mrlightek/lightekmcg-site/customer@sha256:#{'b' * 64}",
      created_by: "operator"}.merge(options))
  end

  def installation(index = SecureRandom.hex(4), **options)
    node = GatekeeperNode.create!(name: "node-#{index}", ip_address: "203.0.113.10", ssh_user: "root")
    GatekeeperInstallation.create!({domain: "client-#{index}.example.com", gatekeeper_node: node,
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
    {"version" => version, "source_sha" => "a" * 40, "image" => @release.image, "notes" => "Test release"}
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
end
