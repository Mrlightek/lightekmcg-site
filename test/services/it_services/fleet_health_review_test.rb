require "test_helper"

class ItServicesFleetHealthReviewTest < ActiveSupport::TestCase
  test "requires an active owner" do
    assert_raises(ArgumentError) { ItServices::FleetHealthReview.call!(owner: nil) }
  end

  test "rejects unbounded fleet review" do
    owner = User.new
    def owner.persisted? = true
    def owner.access_active? = true
    assert_raises(ArgumentError) { ItServices::FleetHealthReview.call!(owner: owner, limit: 10_000) }
  end
end
