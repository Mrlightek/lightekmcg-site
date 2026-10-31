# frozen_string_literal: true

require "test_helper"

class GatekeeperDeviceHeartbeatSweepJobTest < ActiveJob::TestCase
  test "marks stale active devices offline without changing maintenance devices" do
    stale = NetworkManagedDevice.create!(
      name: "Old router", identifier: "old-#{SecureRandom.hex(8)}",
      device_type: "router", status: "active",
      last_seen_at: 10.minutes.ago)
    maintained = NetworkManagedDevice.create!(
      name: "Maintained router", identifier: "maintenance-#{SecureRandom.hex(8)}",
      device_type: "router", status: "maintenance",
      last_seen_at: 10.minutes.ago)
    recent = NetworkManagedDevice.create!(
      name: "Recent router", identifier: "recent-#{SecureRandom.hex(8)}",
      device_type: "router", status: "active",
      last_seen_at: 1.minute.ago)

    GatekeeperDeviceHeartbeatSweepJob.perform_now

    assert_equal "offline", stale.reload.status
    assert_equal "maintenance", maintained.reload.status
    assert_equal "active", recent.reload.status
  end
end
