require "test_helper"

class ItServicesCompletionTest < ActiveSupport::TestCase
  test "completion rejects missing actor" do
    assert_raises(ArgumentError) do
      ItServices::Completion.submit!(request: ItServiceRequest.new, actor: nil,
        summary: "All diagnostic and repair steps completed.")
    end
  end

  test "customer confirmation rejects nonowner" do
    assert_raises(ArgumentError) do
      ItServices::Completion.confirm!(request: ItServiceRequest.new(user_id: 123),
        actor: User.new(id: 124, role: "client"), confirmed: "confirmed", note: "Looks good")
    end
  end
end
