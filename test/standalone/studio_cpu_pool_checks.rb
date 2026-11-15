require_relative "studio_cpu_economy_checks"
require File.join(ROOT, "app/jobs/studio_cpu_lease_sweep_job")
class StudioCpuPoolTest < StudioCpuEconomyTest
  StudioCpuEconomyTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }

  def setup
    super
    @previous_env = ENV.to_h.slice("STUDIO_CPU_DEDICATED_QUEUE", "STUDIO_CPU_SHARED_STORAGE", "STUDIO_CPU_WORKER", "STUDIO_CPU_TENANT_SLOTS", "BLENDER_OUTPUT_ROOT")
    %w[STUDIO_CPU_DEDICATED_QUEUE STUDIO_CPU_SHARED_STORAGE STUDIO_CPU_WORKER STUDIO_CPU_TENANT_SLOTS].each { |key| ENV.delete(key) }
    @work = Dir.mktmpdir("cpu-pool-")
    ENV["BLENDER_OUTPUT_ROOT"] = @work
  end

  def teardown
    %w[STUDIO_CPU_DEDICATED_QUEUE STUDIO_CPU_SHARED_STORAGE STUDIO_CPU_WORKER STUDIO_CPU_TENANT_SLOTS BLENDER_OUTPUT_ROOT].each { |key| ENV.delete(key) }
    @previous_env.each { |key, value| ENV[key] = value }
    FileUtils.rm_rf(@work)
    super
  end

  def perform(op, &block)
    object = Object.new
    object.define_singleton_method(:call, &block)
    Studio::Operations::Dispatcher.stub(:new, ->(_operation) { object }) { ExecuteStudioOperationJob.perform_now(op.id) }
  end

  def test_routing_is_opt_in_and_never_runs_on_regular_worker_when_dedicated
    op = operation(status: "pending")
    assert_equal "studio", ExecuteStudioOperationJob.new(op.id).queue_name
    ENV["STUDIO_CPU_DEDICATED_QUEUE"] = "1"
    assert_raises(ArgumentError) { ExecuteStudioOperationJob.new(op.id).queue_name }
    ENV["STUDIO_CPU_SHARED_STORAGE"] = "1"
    assert_equal "studio_cpu", ExecuteStudioOperationJob.new(op.id).queue_name
    perform(op) { raise "Regular worker must not render" }
    assert_equal "pending", op.reload.status
    assert_nil op.studio_compute_lease
    queued = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == ExecuteStudioOperationJob && job[:args] == [op.id] }.last
    assert_equal "studio_cpu", queued[:queue]
    ENV["STUDIO_CPU_WORKER"] = "1"
    perform(op) { true }
    assert_equal "completed", op.reload.status
    assert op.studio_compute_lease.reload.released_at
  end

  def test_admission_caps_a_tenant_across_projects_but_allows_another_site
    first = operation(status: "pending")
    lease = Studio::Compute::Lease.claim!(first)
    second = operation(status: "pending")
    # Same website, different project: cannot evade the tenant quota.
    other_project = StudioProject.create!(owner: @alice, site: @site, name: "Second project")
    second.update!(studio_project: other_project)
    assert_raises(Studio::Compute::CpuProfile::Busy) { Studio::Compute::Lease.claim!(second) }
    assert_equal "pending", second.reload.status
    other_project.update!(site: @other_site)
    admitted = Studio::Compute::Lease.claim!(second)
    assert admitted.valid?
    assert_nil Studio::Compute::Lease.claim!(first.reload), "Duplicate job cannot claim running work"
    lease.release!; admitted.release!
  end

  def test_expired_attempt_is_reconciled_only_in_authorized_project_and_resumes_same_paid_operation
    op = operation(status: "pending")
    old = Studio::Compute::Lease.claim!(op)
    op.studio_compute_lease.update!(expires_at: 1.second.ago)
    foreign = StudioProject.create!(owner: @bob, site: @other_site, name: "Private")
    Studio::Compute::Lease.reconcile!(foreign.studio_operations)
    assert_equal "running", op.reload.status
    before = DymondBank::Transaction.where(payable: op).count
    action("operations_list", project_id: @project.id)
    assert_equal "failed", op.reload.status
    assert_includes op.error_message, "stopped reporting"
    assert_raises(Studio::Compute::Lease::Lost) { old.check! }
    action("render_resume", operation_id: op.id)
    current = Studio::Compute::Lease.claim!(op.reload)
    old.release!
    assert current.valid?, "Old ensure cannot release a newer token"
    assert_equal before, DymondBank::Transaction.where(payable: op).count
    current.release!
  end

  def test_stale_attempt_cannot_publish_progress_artifacts_or_completion
    op = operation(status: "pending")
    first = Studio::Compute::Lease.claim!(op)
    row = op.studio_compute_lease
    row.update!(expires_at: 1.second.ago)
    Studio::Compute::Lease.reconcile!(StudioOperation.where(id: op.id))
    op.reload.update!(status: "pending")
    current = Studio::Compute::Lease.claim!(op)
    File.write(File.join(@work, "movie.mp4"), "untrusted stale output")
    Studio::Compute::Lease::Current.set(lease: first) do
      assert_raises(Studio::Compute::Lease::Lost) { Studio::Providers::BlenderProvider.new(op).send(:attach_outputs, Pathname(@work)) }
      assert_raises(Studio::Compute::Lease::Lost) { ExecuteStudioOperationJob.new.send(:execute, op) }
    end
    directory = Pathname(@work).join("studio_operations", op.id.to_s)
    FileUtils.mkdir_p(directory)
    File.write(directory.join("cpu-progress.json"), JSON.generate(profile: "cpu_economy", completed_frames: 99))
    Studio::Compute::Lease::Current.set(lease: first) do
      assert_raises(Studio::Compute::Lease::Lost) { Blender::Runner.new(op).send(:record_progress) }
    end
    assert_nil op.reload.metadata["cpu_render_progress"]
    assert_empty op.artifacts
    assert_equal "running", op.reload.status
    assert current.valid?
    current.release!
  end

  def test_sweep_recovers_expired_released_attempt_without_charging_or_enqueuing
    op = operation(status: "pending")
    lease = Studio::Compute::Lease.claim!(op)
    op.studio_compute_lease.update!(expires_at: 1.second.ago)
    lease.release!
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.length
    payments = DymondBank::Transaction.count
    StudioCpuLeaseSweepJob.perform_now
    assert_equal "failed", op.reload.status
    assert_equal jobs, ActiveJob::Base.queue_adapter.enqueued_jobs.length
    assert_equal payments, DymondBank::Transaction.count
    StudioCpuLeaseSweepJob.perform_now
    assert_equal "failed", op.reload.status
  end

  def test_shared_workspace_lock_prevents_old_and_new_attempts_writing_together
    op = operation(status: "pending")
    lease = Studio::Compute::Lease.claim!(op)
    directory = Pathname(@work).join(".locks")
    FileUtils.mkdir_p(directory)
    File.open(directory.join("operation-#{op.id}.lock"), "w") do |lock|
      lock.flock(File::LOCK_EX)
      assert_raises(Studio::Compute::CpuProfile::Busy) { lease.run { flunk "Occupied workspace must not execute" } }
    end
    lease.run { assert_equal lease, Studio::Compute::Lease::Current.lease }
    assert_nil Studio::Compute::Lease::Current.lease
    lease.release!
  end

  def test_failed_job_releases_quota_and_cancellation_preserves_terminal_state
    op = operation(status: "pending")
    assert_raises(RuntimeError) { perform(op) { raise "Renderer failed" } }
    assert_equal "failed", op.reload.status
    assert op.studio_compute_lease.reload.released_at
    assert_nil Studio::Compute::Lease::Current.lease
    op.update!(status: "pending")
    perform(op) { op.update!(status: "cancelled"); Studio::Compute::Lease.check! }
    assert_equal "cancelled", op.reload.status
    assert op.studio_compute_lease.reload.released_at
  end

  def test_heartbeat_cannot_revive_expired_lease_and_new_job_does_not_overwrite_active_attempt
    op = operation(status: "pending")
    lease = Studio::Compute::Lease.claim!(op)
    perform(op) { flunk "Duplicate job must not render" }
    assert_equal "running", op.reload.status
    op.studio_compute_lease.update!(expires_at: 1.second.ago)
    assert_raises(Studio::Compute::Lease::Lost) { lease.heartbeat! }
    lease.release!
    action("operations_list", project_id: @project.id)
    assert_equal "failed", op.reload.status, "An expired worker ensure must not hide an abandoned running attempt"
  end

  def test_old_exception_handler_cannot_fail_or_release_a_newer_attempt
    op = operation(status: "pending")
    replacement = nil
    perform(op) do
      op.studio_compute_lease.update!(expires_at: 1.second.ago)
      Studio::Compute::Lease.reconcile!(StudioOperation.where(id: op.id))
      op.reload.update!(status: "pending")
      replacement = Studio::Compute::Lease.claim!(op)
      raise "Old worker woke up with an error"
    end
    assert_equal "running", op.reload.status
    assert replacement.valid?
    assert_nil op.error_message
    replacement.release!
  end

  def test_quota_deferral_does_not_reset_a_concurrently_claimed_operation
    op = operation(status: "pending")
    replacement = nil
    original = Studio::Compute::Lease.method(:claim!)
    Studio::Compute::Lease.stub(:claim!, ->(record) { replacement = original.call(record); raise Studio::Compute::CpuProfile::Busy }) do
      perform(op) { flunk "Quota deferral must not render" }
    end
    assert_equal "running", op.reload.status
    assert replacement.valid?
    replacement.release!
  end

  def test_real_render_publishes_artifacts_under_live_lease_and_releases_it
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"] == "1"
    op = operation(status: "pending")
    perform(op) { Rails.stub(:root, Pathname(ROOT)) { Studio::Providers::BlenderProvider.new(op).call } }
    assert_equal "completed", op.reload.status
    assert op.studio_compute_lease.reload.released_at
    assert op.artifacts.find_by!(filename: "movie.mp4").file.attached?
    assert_equal 3, op.metadata.dig("cpu_render_progress", "completed_frames")
    refute Pathname(@work).join("studio_operations", op.id.to_s, "cpu-frames").exist?
  end
end
