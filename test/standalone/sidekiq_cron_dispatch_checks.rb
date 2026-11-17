require 'minitest/autorun'
require 'active_support/all'
require 'active_job'
require 'sidekiq/cron/job'
require 'yaml'
require 'pathname'
ROOT = Pathname.new(File.expand_path('../..', __dir__))
require ROOT.join('app/jobs/application_job')
%w[gatekeeper/fleet/sweep_job gatekeeper/hosting/recovery_job gatekeeper_device_heartbeat_sweep_job lightek_pwa/member_capacity_job lightek_pwa/commercial_recovery_job].each do |path|
  require ROOT.join('app/jobs', path)
end
# Redis schedule-history writes are outside this enqueue regression. Keep the
# actual pinned Cron engine and real Active Job configured enqueue path.
class CronDispatchFixture < Sidekiq::Cron::Job
  def save_last_enqueue_time; end
  def add_jid_history(_jid); end
end
class SidekiqCronDispatchTest < Minitest::Test
  def setup
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.logger = Logger.new(File::NULL)
    @schedule = YAML.load_file(ROOT.join('config/schedule.yml'))
  end
  def test_scheduled_recovery_and_capacity_jobs_enqueue_real_active_job_payloads
    %w[gatekeeper_fleet_recovery gatekeeper_hosting_recovery gatekeeper_device_heartbeat_sweep pwa_member_capacity_alerts pwa_commercial_recovery].each do |name|
      spec = @schedule.fetch(name)
      job = CronDispatchFixture.new(spec.merge('name'=>name, 'fetch_missing_args'=>false, 'status'=>'enabled'))
      job.enque!
      payload = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      assert_equal spec.fetch('class'), payload.fetch(:job).name
      assert_equal spec.fetch('queue'), payload.fetch(:queue)
      assert_equal [], payload.fetch(:args)
    end
  end
  def test_every_schedule_explicitly_selects_active_job_so_redis_reloads_do_not_depend_on_class_detection
    @schedule.each do |name, spec|
      job = CronDispatchFixture.new(spec.merge('name'=>name, 'fetch_missing_args'=>false, 'status'=>'enabled'))
      # Same detection method the real cron engine uses when loading a class
      # is unavailable, as can happen during scheduler startup/reload.
      assert job.is_active_job?(nil), "#{name} loses Active Job dispatch during class loading"
      assert_equal true, spec.fetch('active_job'), name
    end
  end
end
