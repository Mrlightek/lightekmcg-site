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
    existing.expect(:status, "disabled")
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

  test "rejects invalid job names" do
    assert_raises(ArgumentError) do
      Gatekeeper::CronManagement.create!(
        name: "x", job_class: "GatekeeperDeviceHeartbeatSweepJob",
        cron: "*/5 * * * *")
    end
  end
end
