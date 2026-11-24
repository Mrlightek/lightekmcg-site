require "test_helper"

class ItServicesDiagnosticRunbooksTest < ActiveSupport::TestCase
  test "catalog contains no executable commands" do
    assert_equal %w[backup connectivity performance security], ItServices::DiagnosticRunbooks::CATALOG.keys.sort
    ItServices::DiagnosticRunbooks::CATALOG.each_value do |runbook|
      assert runbook.fetch("checks").all? { |check| check.is_a?(String) && check.present? }
    end
  end

  test "rejects unknown runbooks without device access" do
    assert_raises(ArgumentError) do
      ItServices::DiagnosticRunbooks.for_request!(request: ItServiceRequest.new,
        actor: nil, code: "arbitrary_shell")
    end
  end
end
