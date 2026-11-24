require "test_helper"

class ItServicesIncidentEscalationTest < ActiveSupport::TestCase
  test "security and backup findings receive elevated priority" do
    assert_equal "high", ItServices::IncidentEscalation.priority_for("endpoint_protection_alert")
    assert_equal "high", ItServices::IncidentEscalation.priority_for("backup_failed")
    assert_equal "medium", ItServices::IncidentEscalation.priority_for("heartbeat_stale")
  end

  test "no remote execution is authorized by escalation" do
    source = ItServices::IncidentEscalation
    assert_raises(ArgumentError) { source.call!(incident: ItManagedDeviceIncident.new(status: "resolved")) }
  end
end
