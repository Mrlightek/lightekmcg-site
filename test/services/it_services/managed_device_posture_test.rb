require "test_helper"

class ItServicesManagedDevicePostureTest < ActiveSupport::TestCase
  def owner
    @owner ||= User.new.tap do |user|
      user.id = 101
      def user.persisted? = true
    end
  end

  def device(status:, enrolled_at: Time.current, last_seen_at: Time.current)
    NetworkManagedDevice.new(owner_id: owner.id, status: status,
      enrolled_at: enrolled_at, last_seen_at: last_seen_at)
  end

  test "active device with recent heartbeat is only connectivity observed" do
    report = ItServices::ManagedDevicePosture.evaluate(device: device(status: "active"), owner: owner)
    assert_equal "attention_required", report[:status]
    assert_includes report[:findings], "telemetry_missing_or_stale"
    assert_equal false, report[:remote_execution_authorized]
    assert_match(/have not been verified/, report[:limitations])
  end

  test "maintenance device is not healthy" do
    report = ItServices::ManagedDevicePosture.evaluate(device: device(status: "maintenance"), owner: owner)
    assert_equal "attention_required", report[:status]
    assert_includes report[:findings], "not_active"
  end

  test "missing heartbeat is flagged even on active device" do
    report = ItServices::ManagedDevicePosture.evaluate(
      device: device(status: "active", last_seen_at: nil), owner: owner)
    assert_includes report[:findings], "heartbeat_missing"
  end

  test "stale heartbeat is flagged even when status is offline" do
    report = ItServices::ManagedDevicePosture.evaluate(
      device: device(status: "offline", last_seen_at: 1.hour.ago), owner: owner)
    assert_includes report[:findings], "heartbeat_stale"
  end

  test "rejects devices owned by a different account" do
    assert_raises(ArgumentError) do
      ItServices::ManagedDevicePosture.evaluate(
        device: NetworkManagedDevice.new(owner_id: 999, status: "active"), owner: owner)
    end
  end
end
