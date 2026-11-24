# frozen_string_literal: true

require "test_helper"

class GatekeeperDeviceApiTest < ActionDispatch::IntegrationTest
  PASSWORD = "Test-password-123!"

  def setup
    @device = NetworkManagedDevice.create!(
      name: "Test router", identifier: "router-#{SecureRandom.hex(8)}",
      device_type: "router", management_protocol: "agent")
    @token = @device.rotate_enrollment_token!
  end

  def send_action(action, token: @token, device: @device, **attributes)
    post gatekeeper_device_path,
      params: { method_type: action, identifier: device.identifier }.merge(attributes),
      headers: { "Authorization" => "Bearer #{token}" },
      as: :json
  end

  test "device enrolls then heartbeats with a valid token" do
    send_action("device_enroll")
    assert_response :success
    assert @device.reload.enrolled_at.present?

    send_action("device_heartbeat")
    assert_response :success
    assert @device.reload.last_seen_at.present?
  end

  test "rejects invalid bearer token" do
    send_action("device_enroll", token: "incorrect")
    assert_response :unauthorized
    assert_nil @device.reload.enrolled_at
  end

  test "does not allow heartbeat before enrollment" do
    send_action("device_heartbeat")
    assert_response :forbidden
  end

  test "offline enrolled device recovers on authenticated heartbeat" do
    send_action("device_enroll")
    assert_response :success
    @device.update!(status: "offline", last_seen_at: 10.minutes.ago)

    send_action("device_heartbeat")
    assert_response :success
    assert_equal "active", @device.reload.status
    assert_operator @device.last_seen_at, :>, 1.minute.ago
  end

  test "maintenance status prevents heartbeat" do
    send_action("device_enroll")
    @device.update!(status: "maintenance")
    send_action("device_heartbeat")
    assert_response :forbidden
    assert_equal "maintenance", @device.reload.status
  end

  test "retired devices cannot enroll again" do
    @device.update!(status: "retired")
    send_action("device_enroll")
    assert_response :forbidden
  end

  test "unknown methods cannot execute" do
    send_action("delete_all_devices")
    assert_response :bad_request
  end

  test "scheduled checks reach only the intended device and accept a result once within the window" do
    owner = create_user
    operator = create_user(role: "super_admin")
    send_action("device_enroll")
    @device.update!(owner: owner)
    post session_path, params: { email_address: owner.email_address, password: PASSWORD }
    assert_response :redirect
    post managed_device_monitoring_it_service_requests_path, params: { device_id: @device.id, enabled: "true" }
    assert_redirected_to it_service_requests_path
    assert @device.reload.managed_monitoring_enabled?
    other = NetworkManagedDevice.create!(name: "Other device", identifier: "other-#{SecureRandom.hex(8)}",
      device_type: "computer", owner: create_user)
    other_token = other.rotate_enrollment_token!
    send_action("device_enroll", device: other, token: other_token)
    other.update!(managed_monitoring_enabled: true)
    start = 1.hour.from_now.change(usec: 0)
    check = ItServices::EndpointMaintenance.approve!(device: @device, actor: operator,
      code: "refresh_inventory", scheduled_at: start.iso8601)
    result = { action_id: check.id, nonce: check.request_nonce,
      result: { status: "ok", observation: "Platform: Linux" } }

    send_action("device_heartbeat")
    assert_empty response.parsed_body.fetch("maintenance_actions")
    send_action("device_maintenance_report", **result)
    assert_response :unprocessable_entity

    travel_to start do
      send_action("device_heartbeat", device: other, token: other_token)
      assert_empty response.parsed_body.fetch("maintenance_actions")
      send_action("device_maintenance_report", device: other, token: other_token, **result)
      assert_response :not_found

      send_action("device_heartbeat")
      assert_equal [check.id], response.parsed_body.fetch("maintenance_actions").pluck("id")
      send_action("device_maintenance_report", **result)
      assert_response :success
      assert_equal "reported", check.reload.status
      send_action("device_maintenance_report", **result)
      assert_response :unprocessable_entity
    end
  end

  test "expired, cancelled and revoked checks cannot report" do
    owner = create_user
    operator = create_user(role: "super_admin")
    send_action("device_enroll")
    @device.update!(owner: owner, managed_monitoring_enabled: true)
    approve = -> { ItServices::EndpointMaintenance.approve!(device: @device,
      actor: operator, code: "refresh_inventory") }
    expired, cancelled, revoked = Array.new(3) { approve.call }
    expired.update!(expires_at: 1.second.ago)
    ItServices::EndpointMaintenance.cancel!(device: @device, action_id: cancelled.id,
      actor: owner, owner_only: true)

    [expired, cancelled].each do |check|
      send_action("device_maintenance_report", action_id: check.id, nonce: check.request_nonce,
        result: { status: "ok", observation: "Platform: Linux" })
      assert_response :unprocessable_entity
    end

    post session_path, params: { email_address: owner.email_address, password: PASSWORD }
    assert_response :redirect
    post managed_device_monitoring_it_service_requests_path, params: { device_id: @device.id, enabled: "false" }
    assert_redirected_to it_service_requests_path
    assert_equal "cancelled", revoked.reload.status
    send_action("device_maintenance_report", action_id: revoked.id, nonce: revoked.request_nonce,
      result: { status: "ok", observation: "Platform: Linux" })
    assert_response :forbidden
    @device.rotate_enrollment_token!
    send_action("device_heartbeat")
    assert_response :unauthorized
  end

  test "customer cannot consent or cancel a check for a different tenant" do
    owner = create_user
    send_action("device_enroll")
    @device.update!(owner: owner, managed_monitoring_enabled: false)
    other = create_user
    post session_path, params: { email_address: other.email_address, password: PASSWORD }
    assert_response :redirect

    post managed_device_monitoring_it_service_requests_path, params: { device_id: @device.id, enabled: "true" }
    assert_response :not_found
    assert_not @device.reload.managed_monitoring_enabled?
    post cancel_device_check_it_service_requests_path, params: { device_id: @device.id, action_id: 1 }
    assert_response :not_found
  end

  private

  def create_user(role: "client")
    User.create!(email_address: "it-endpoint-#{SecureRandom.hex(8)}@example.test",
      first_name: "Endpoint", last_name: "Test", password: PASSWORD, role: role)
  end
end
