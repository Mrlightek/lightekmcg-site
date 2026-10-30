# frozen_string_literal: true

require "test_helper"

class GatekeeperDeviceApiTest < ActionDispatch::IntegrationTest
  def setup
    @device = NetworkManagedDevice.create!(
      name: "Test router", identifier: "router-#{SecureRandom.hex(8)}",
      device_type: "router", management_protocol: "agent")
    @token = @device.rotate_enrollment_token!
  end

  def send_action(action, token: @token)
    post gatekeeper_device_path,
      params: { method_type: action, identifier: @device.identifier },
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
end
