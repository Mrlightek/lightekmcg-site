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

  test "retained telemetry cannot open findings after monitoring consent is revoked" do
    owner = create_customer
    device = create_connected_device(owner, managed_monitoring_enabled: false,
      health_telemetry: { "disk_percent" => 99 }, health_telemetry_at: Time.current)

    assert_no_difference "ItManagedDeviceIncident.count" do
      assert_nil ItServices::ManagedFleetIncidents.reconcile!(device: device, owner: owner)
    end
  end

  test "a fresh authenticated heartbeat resolves the stale heartbeat finding" do
    owner = create_customer
    device = create_connected_device(owner, managed_monitoring_enabled: true,
      status: "offline", last_seen_at: 10.minutes.ago)
    first = ItServices::ManagedFleetIncidents.reconcile!(device: device, owner: owner)
    incident = ItManagedDeviceIncident.find_by!(id: first.fetch(:opened), finding_code: "heartbeat_stale")
    device.update!(status: "active", last_seen_at: Time.current)

    checked = ItServices::ManagedFleetIncidents.reconcile!(device: device, owner: owner)

    assert_includes checked.fetch(:resolved), incident.id
    assert_equal "resolved", incident.reload.status
  end

  test "a reported patch count opens an owner-scoped finding" do
    owner = create_customer
    operator = create_customer(role: "super_admin")
    device = create_connected_device(owner, managed_monitoring_enabled: true)
    check = ItServices::EndpointMaintenance.approve!(device: device, actor: operator, code: "check_patch_status")
    assert_raises(ArgumentError) do
      ItServices::EndpointMaintenance.report!(device: device, action_id: check.id, nonce: check.request_nonce,
        result: { status: "ok", observation: "Inconsistent", available_update_count: 3 })
    end
    ItServices::EndpointMaintenance.report!(device: device, action_id: check.id, nonce: check.request_nonce,
      result: { status: "warning", observation: "Three updates observed", available_update_count: 3 })

    review = ItServices::ManagedFleetIncidents.reconcile!(device: device, owner: owner)

    assert ItManagedDeviceIncident.open_incidents.exists?(
      id: review.fetch(:opened), owner_id: owner.id, finding_code: "patches_available")
  end

  private

  def create_customer(role: "client")
    User.create!(email_address: "it-fleet-#{SecureRandom.hex(8)}@example.test", first_name: "Fleet",
      last_name: "Test", role: role, password: "Test-password-123!")
  end

  def create_connected_device(owner, **attributes)
    NetworkManagedDevice.create!({ name: "Fleet test", identifier: "fleet-#{SecureRandom.hex(8)}",
      device_type: "computer", owner: owner, status: "active", enrolled_at: Time.current,
      last_seen_at: Time.current }.merge(attributes))
  end
end
