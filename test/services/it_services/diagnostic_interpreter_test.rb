require "test_helper"

class ItServicesDiagnosticInterpreterTest < ActiveSupport::TestCase
  test "does not produce a report without customer authorization" do
    customer = User.new(id: 101)
    request = ItServiceRequest.new(user: customer)
    assert_raises(ArgumentError) { ItServices::DiagnosticInterpreter.call!(request: request, actor: customer) }
  end

  test "does not expose another customer's device report" do
    customer = User.new(id: 101)
    outsider = User.new(id: 202)
    request = ItServiceRequest.new(user: customer)
    assert_raises(ArgumentError) { ItServices::DiagnosticInterpreter.call!(request: request, actor: outsider) }
  end
end
