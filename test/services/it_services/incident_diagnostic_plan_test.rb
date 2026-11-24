require "test_helper"

class ItServicesIncidentDiagnosticPlanTest < ActiveSupport::TestCase
  test "security alerts receive a non-executable security plan" do
    incident = ItManagedDeviceIncident.new(finding_code: "endpoint_protection_alert")
    plan = ItServices::IncidentDiagnosticPlan.for(incident)
    assert_equal "security", plan["runbook"]
    assert_equal "manual_only", plan["execution"]
    assert_equal false, plan["commands_executed"]
  end

  test "unrecognized findings fail closed" do
    incident = ItManagedDeviceIncident.new(finding_code: "unrecognized")
    plan = ItServices::IncidentDiagnosticPlan.for(incident)
    assert_nil plan["runbook"]
    assert_equal false, plan["repair_verified"]
  end
end
