# frozen_string_literal: true

require "test_helper"

class GatekeeperCronManagementTest < ActiveSupport::TestCase
  test "rejects job classes outside the approved registry" do
    assert_raises(ArgumentError) do
      Gatekeeper::CronManagement.create!(
        name: "unexpected_job", job_class: "Kernel", cron: "*/5 * * * *")
    end
  end

  test "rejects invalid schedules before accessing Redis" do
    assert_raises(ArgumentError) do
      Gatekeeper::CronManagement.create!(
        name: "invalid_schedule", job_class: "GatekeeperDeviceHeartbeatSweepJob",
        cron: "not a cron expression")
    end
  end

  test "rejects management of non-dashboard schedules" do
    assert_raises(ArgumentError) do
      Gatekeeper::CronManagement.managed_job!("gatekeeper_device_heartbeat_sweep")
    end
  end

  test "updating a disabled schedule preserves its paused state" do
    existing = Minitest::Mock.new
    existing.expect(:name, "dashboard_test_schedule")
    existing.expect(:name, "dashboard_test_schedule")
    existing.expect(:status, "disabled")
    existing.expect(:klass, "GatekeeperDeviceHeartbeatSweepJob")
    replacement = Minitest::Mock.new
    replacement.expect(:save, true)
    replacement.expect(:disable!, true)

    Sidekiq::Cron::Job.stub(:find, ->(_name) { existing }) do
      Sidekiq::Cron::Job.stub(:new, replacement) do
        Gatekeeper::CronManagement.update!(
          name: "dashboard_test_schedule",
          cron: "*/10 * * * *",
          job_class: "GatekeeperDeviceHeartbeatSweepJob")
      end
    end

    existing.verify
    replacement.verify
  end

  test "update rejects existing unapproved job classes" do
    unexpected = Struct.new(:klass).new("Kernel")
    Sidekiq::Cron::Job.stub(:find, unexpected) do
      assert_raises(ArgumentError) do
        Gatekeeper::CronManagement.update!(
          name: "dashboard_unapproved", cron: "*/5 * * * *",
          job_class: "GatekeeperDeviceHeartbeatSweepJob")
      end
    end
  end

  test "run now refuses a job class outside the approved registry" do
    unexpected = Struct.new(:klass).new("Kernel")
    Sidekiq::Cron::Job.stub(:find, unexpected) do
      assert_raises(ArgumentError) do
        Gatekeeper::CronManagement.run_now!(name: "dashboard_unapproved")
      end
    end
  end

  test "run now rejects non-dashboard jobs" do
    assert_raises(ArgumentError) do
      Gatekeeper::CronManagement.run_now!(name: "susu_cycle_advance")
    end
  end

  test "delete rejects non-dashboard jobs" do
    assert_raises(ArgumentError) do
      Gatekeeper::CronManagement.destroy!(name: "susu_cycle_advance")
    end
  end

  test "toggle rejects non-dashboard jobs" do
    assert_raises(ArgumentError) do
      Gatekeeper::CronManagement.toggle!(name: "susu_cycle_advance")
    end
  end

  test "rejects invalid job names" do
    assert_raises(ArgumentError) do
      Gatekeeper::CronManagement.create!(
        name: "x", job_class: "GatekeeperDeviceHeartbeatSweepJob",
        cron: "*/5 * * * *")
    end
  end
end
