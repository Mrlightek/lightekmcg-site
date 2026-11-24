require "test_helper"

class ItServicesManagedFleetRecoveryTest < ActiveSupport::TestCase
  def device
    NetworkManagedDevice.new(status: "active", enrolled_at: 1.day.ago,
      last_seen_at: Time.current)
  end

  test "security alert does not resolve without explicit healthy telemetry" do
    posture = { telemetry_fresh: true, reported_telemetry: {} }
    assert_not ItServices::ManagedFleetIncidents.recovery_verified?(
      code: "endpoint_protection_alert", device: device, posture: posture)
    posture[:reported_telemetry]["endpoint_protection"] = "healthy"
    assert ItServices::ManagedFleetIncidents.recovery_verified?(
      code: "endpoint_protection_alert", device: device, posture: posture)
  end

  test "backup failure needs fresh reported success" do
    posture = { telemetry_fresh: false, reported_telemetry: { "backup_status" => "success" } }
    assert_not ItServices::ManagedFleetIncidents.recovery_verified?(
      code: "backup_failed", device: device, posture: posture)
    posture[:telemetry_fresh] = true
    assert ItServices::ManagedFleetIncidents.recovery_verified?(
      code: "backup_failed", device: device, posture: posture)
  end

  test "retired incidents cannot be auto-resolved" do
    assert_not ItServices::ManagedFleetIncidents.recovery_verified?(
      code: "retired", device: device,
      posture: { telemetry_fresh: true, reported_telemetry: {} })
  end
end
