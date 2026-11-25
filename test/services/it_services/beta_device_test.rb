# frozen_string_literal: true

require "test_helper"

class ItServicesBetaDeviceTest < ActiveSupport::TestCase
  TEST_HOST = "batch-d-msp-r1.staging.example.test"

  setup do
    skip "Run with the combined MSP staging schema" unless User.column_names.include?("staging_access_expires_at") &&
      NetworkManagedDevice.column_names.include?("managed_monitoring_enabled")

    @previous_target = ENV["LIGHTEK_RELEASE_ASSURANCE_TARGET"]
    @previous_host = ENV["LIGHTEK_DEPLOYED_SITE_HOST"]
    @restore_environment = true
    ENV["LIGHTEK_RELEASE_ASSURANCE_TARGET"] = "1"
    ENV["LIGHTEK_DEPLOYED_SITE_HOST"] = TEST_HOST
    @tester = User.create!(email_address: "beta-#{SecureRandom.random_number(1_000_000) + 1}@example.test",
      first_name: "Staging", last_name: "Tester", role: "client", password: SecureRandom.hex(16),
      staging_access_expires_at: 1.hour.from_now)
  end

  teardown do
    if @restore_environment
      ENV["LIGHTEK_RELEASE_ASSURANCE_TARGET"] = @previous_target
      ENV["LIGHTEK_DEPLOYED_SITE_HOST"] = @previous_host
    end
  end

  test "one device is reused and rotation and unenrollment invalidate tokens" do
    device, first = ItServices::BetaDevice.issue!(@tester)
    assert device.authenticate_enrollment_token?(first)
    assert device.managed_monitoring_enabled?

    replacement, second = ItServices::BetaDevice.issue!(@tester)
    assert_equal device.id, replacement.id
    assert_not_equal first, second
    refute replacement.authenticate_enrollment_token?(first)
    assert replacement.authenticate_enrollment_token?(second)

    ItServices::BetaDevice.revoke!(@tester)
    assert_equal "retired", replacement.reload.status
    assert_nil replacement.enrollment_token_digest
    refute replacement.authenticate_enrollment_token?(second)
  end

  test "an expired account fails token authentication and cannot renew" do
    device, token = ItServices::BetaDevice.issue!(@tester)
    @tester.update!(staging_access_expires_at: 1.second.ago)
    refute device.reload.authenticate_enrollment_token?(token)
    assert_raises(ItServices::BetaDevice::Denied) { ItServices::BetaDevice.issue!(@tester) }
  end

  test "only the exact configured isolated staging host is eligible" do
    assert ItServices::BetaDevice.staging_host?(TEST_HOST)
    refute ItServices::BetaDevice.staging_host?("lightekmcg.com")
    refute ItServices::BetaDevice.staging_host?("batch-d-other.staging.example.test")
    refute ItServices::BetaDevice.staging_host?(nil)
  end
end
