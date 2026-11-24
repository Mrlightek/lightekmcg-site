# frozen_string_literal: true

require "active_record"
require "action_controller"
require "action_dispatch"
require "active_job"
require "minitest/autorun"
require "active_support/security_utils"

# Exercise real models, foreign keys, transactions and migration against an
# isolated SQL database. PostgreSQL JSONB columns use SQLite's JSON type here.
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::ConnectionAdapters::SQLite3::TableDefinition.alias_method :jsonb, :json
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :role }
  create_table(:provisioning_requests)
  create_table(:gatekeeper_operations)
end

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  # The evidence storage service is outside this database contract fixture.
  def self.has_one_attached(*) = nil
end
class User < ApplicationRecord; end
class ProvisioningRequest < ApplicationRecord; end
class GatekeeperOperation < ApplicationRecord; end

require_relative "../../app/services/lightek_people/lifecycle_access"
require_relative "../../db/migrate/20261124210000_create_release_assurance"
CreateReleaseAssurance.new.migrate(:up)
%w[source policy readiness github_checks beta_access production_promotion].each { |name| require_relative "../../app/services/release_assurance/#{name}" }
%w[candidate environment tester assignment run defect].each { |name| require_relative "../../app/models/release_assurance/#{name}" }

module Gatekeeper
  class WebsiteDeployment
    class Invalid < StandardError; end

    def self.authorize!(actor)
      raise Invalid unless actor.persisted? && actor.role == "super_admin"
    end
  end
end

class ReleaseAssuranceRecordsTest < Minitest::Test
  include ReleaseAssurance

  def setup
    @operator = User.create!(role: "super_admin")
    @candidate = Candidate.create!(operator: @operator, name: "Combined MSP", profile: "msp",
      publication_key: SecureRandom.uuid, selectors: Source::MSP, source_sha: "a" * 40, state: "published")
    @environment = @candidate.environments.create!(provisioning_request: ProvisioningRequest.create!,
      hostname: "batch-d-#{@candidate.id}.staging.example.org", budget_cents: 4800,
      expires_at: 12.hours.from_now, state: "ready")
    @readiness = Readiness.new(@candidate)
  end

  def test_readiness_enforces_evidence_kind_and_current_environment
    @readiness.required.each { |key, kind| run_check(key, kind) unless key == "windows_remote" }

    run_check("windows_remote", "simulated")
    assert_includes @readiness.evaluation[:blockers], "Windows remote — evidence missing"
    assert_raises(Policy::Denied) { @readiness.approve!(@operator, evidence_digest: @readiness.evaluation[:digest]) }

    run_check("windows_remote", "real_world")
    assert_empty @readiness.evaluation[:blockers]
    refute @readiness.evaluation[:approved]

    @readiness.approve!(@operator, evidence_digest: @readiness.evaluation[:digest])
    assert @readiness.evaluation[:approved]
    assert @readiness.authorize_promotion!(@operator, source_sha: @candidate.source_sha)[:approved]
    assert_raises(Policy::Denied) { @readiness.authorize_promotion!(@operator, source_sha: "b" * 40) }

    @environment.update!(expires_at: 1.minute.ago)
    refute @readiness.evaluation[:approved]
    assert_includes @readiness.evaluation[:blockers], "Deploy an active staging environment"
  end

  def test_route_helpers_resolve_to_the_host_dashboard
    routes = ActionDispatch::Routing::RouteSet.new
    routes.draw { instance_eval(File.read(File.expand_path("../../config/routes/release_assurance.rb", __dir__))) }
    helpers = routes.url_helpers
    assert_equal "/dashboard/release_assurance/register_tester", helpers.register_tester_dashboard_release_assurance_index_path
    assert_equal "/dashboard/release_assurance/12/evidence/3", helpers.evidence_dashboard_release_assurance_path(12, run_id: 3)
    assert_equal "/dashboard/release_assurance/12/rollback", helpers.rollback_dashboard_release_assurance_path(12)
    assert_equal "/release-beta", helpers.release_beta_path
  end

  def test_production_verification_binds_main_and_candidate_to_the_same_tree
    @readiness.required.each { |key, kind| run_check(key, kind) }
    @readiness.approve!(@operator, evidence_digest: @readiness.evaluation.fetch(:digest))
    revision = "b" * 40
    tree = "c" * 40
    resolver = Module.new do
      def refresh_ci!(*) = nil

      define_method(:github_sha) do |path|
        case path
        when "git/ref/heads/main" then { "object" => { "sha" => revision } }
        when "git/commits/#{revision}", "git/commits/#{'a' * 40}" then { "tree" => { "sha" => tree } }
        end
      end
    end
    verifier = Class.new(ProductionPromotion)
    verifier.singleton_class.prepend(resolver)
    decision = verifier.verify!(@candidate, revision: revision, tree: tree, profile: "msp")
    assert_equal revision, decision.fetch(:production_sha)
    assert_equal @candidate.source_sha, decision.fetch(:source_sha)
    assert_raises(Policy::Denied) { verifier.verify!(@candidate, revision: "d" * 40, tree: tree, profile: "msp") }
    assert_raises(Policy::Denied) { verifier.verify!(@candidate, revision: revision, tree: "d" * 40, profile: "msp") }
    assert_raises(Policy::Denied) { verifier.verify!(@candidate, revision: revision, tree: tree, profile: "standard") }

    @environment.update!(expires_at: 1.minute.ago)
    assert_raises(Policy::Denied) { verifier.verify!(@candidate, revision: revision, tree: tree, profile: "msp") }
  end

  def test_a_new_passing_receipt_does_not_preserve_a_stale_approval
    @readiness.required.each { |key, kind| run_check(key, kind) }
    previous_digest = @readiness.evaluation.fetch(:digest)
    @readiness.approve!(@operator, evidence_digest: previous_digest)
    run_check("browser_smoke", "automated")

    assert_empty @readiness.evaluation[:blockers]
    refute @readiness.evaluation[:approved]
    assert_raises(Policy::Denied) { @readiness.approve!(@operator, evidence_digest: previous_digest) }
  end

  def test_failed_runs_block_promotion_until_retested
    @readiness.required.each { |key, kind| run_check(key, kind) }
    failed = run_check("application", "automated", result: "failed")
    passed = run_check("application", "automated")
    assert_includes @readiness.evaluation[:blockers], "Resolve failed checks and record retests"

    @candidate.defects.create!(run: failed, retest: passed, status: "verified")
    assert_empty @readiness.evaluation[:blockers]
  end

  def test_offboarding_or_retirement_revokes_beta_assignment
    tester = Tester.create!(operator: @operator, name: "Tester", email: "Tester@example.test", platform: "windows",
      device_profile: "Disposable Windows VM", consented_at: Time.current)
    assignment = @environment.assignments.create!(tester: tester, scenario: "windows_remote",
      invite_digest: SecureRandom.hex(32), expires_at: 2.hours.from_now)

    assert assignment.active?
    tester.update!(offboarded_at: Time.current)
    refute assignment.reload.active?
    assert_equal "tester@example.test", tester.email
  end

  def test_evidence_is_revision_bound_and_candidate_is_operator_bound
    run = @candidate.runs.build(check_key: "application", kind: "automated", result: "passed", source_sha: "b" * 40)
    refute run.valid?
    assert_includes run.errors[:source_sha], "must match the candidate"

    another_operator = User.create!(role: "super_admin")
    assert_raises(Policy::Denied) { Policy.authorize!(another_operator, @candidate) }
  end

  def test_github_import_rejects_unrelated_and_skipped_runs
    importer = GithubChecks.new(@candidate)
    run = {
      "id" => 10, "run_attempt" => 1, "path" => ".github/workflows/ci.yml", "head_sha" => @candidate.source_sha,
      "head_branch" => @candidate.publication_ref, "head_repository" => { "full_name" => GithubChecks::REPOSITORY },
      "event" => "push", "status" => "completed", "conclusion" => "success"
    }

    response = lambda do |path, **|
      case path
      when "actions/workflows/ci.yml/runs"
        { "workflow_runs" => [run, run.merge("id" => 22, "head_sha" => "f" * 40)] }
      when "actions/runs/10/attempts/1/jobs"
        { "jobs" => [{ "name" => "test", "conclusion" => "skipped" }] }
      else
        { "workflow_runs" => [] }
      end
    end

    importer.define_singleton_method(:request, &response)
    importer.sync!
    receipt = @candidate.runs.find_by!(check_key: "application")
    assert_equal "github:10:1", receipt.external_id
    assert_equal "blocked", receipt.result
  end

  private

  def run_check(key, kind, result: "passed")
    @candidate.runs.create!(check_key: key, kind: kind, result: result, source_sha: @candidate.source_sha,
      environment: (Readiness::CI.key?(key) ? nil : @environment))
  end
end
