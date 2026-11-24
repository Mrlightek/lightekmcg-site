require "test_helper"

class ItServicesManagedFleetIncidentsTest < ActiveSupport::TestCase
  test "requires owner authorization" do
    assert_raises(ArgumentError) do
      ItServices::ManagedFleetIncidents.reconcile!(
        device: NetworkManagedDevice.new(owner_id: 99), owner: nil)
    end
  end

  test "rejects unbounded owner sweeps" do
    user = User.new
    def user.persisted? = true
    def user.access_active? = true
    assert_raises(ArgumentError) do
      ItServices::ManagedFleetIncidents.review_owner!(owner: user, limit: 251)
    end
  end

  test "incidents cannot be reassigned across owners" do
    device = NetworkManagedDevice.new(owner_id: 3)
    owner = User.new
    owner.id = 4
    incident = ItManagedDeviceIncident.new(network_managed_device: device, owner: owner,
      finding_code: "heartbeat_stale", status: "open",
      first_observed_at: Time.current, last_observed_at: Time.current)
    assert_not incident.valid?
    assert incident.errors[:owner].present?
  end
end
