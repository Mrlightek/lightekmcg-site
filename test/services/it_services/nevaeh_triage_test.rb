require "test_helper"

class ItServicesNevaehTriageTest < ActiveSupport::TestCase
  test "rejects cross-customer triage" do
    customer = User.new(id: 101)
    outsider = User.new(id: 202)
    request = ItServiceRequest.new(user: customer, delivery_mode: "remote")
    assert_raises(ArgumentError) { ItServices::NevaehTriage.call!(request: request, actor: outsider) }
  end

  test "unlinked remote device requires specialist" do
    customer = User.new(id: 101)
    request = ItServiceRequest.new(user: customer, delivery_mode: "remote", service_code: "optimization")
    # Unsaved actors are deliberately not accepted as authorized customers.
    assert_raises(ArgumentError) { ItServices::NevaehTriage.call!(request: request, actor: customer) }
  end
end
