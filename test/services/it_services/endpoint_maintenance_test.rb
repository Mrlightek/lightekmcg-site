require "test_helper"

class ItServicesEndpointMaintenanceTest < ActiveSupport::TestCase
  test "only explicitly supported maintenance codes are permitted" do
    assert_equal %w[refresh_inventory check_patch_status check_backup_status check_endpoint_protection verify_backup_recovery stage_backup_restore cutover_backup_restore deploy_apt_patch deploy_windows_patch deploy_macos_patch],
      ItDeviceMaintenanceAction::ACTIONS
    assert_not_includes ItDeviceMaintenanceAction::ACTIONS, "install_patch"
    assert_not_includes ItDeviceMaintenanceAction::ACTIONS, "restore_backup"
    assert_not_includes ItDeviceMaintenanceAction::ACTIONS, "execute_shell"
  end

  test "unowned and unenrolled devices cannot receive actions" do
    device = NetworkManagedDevice.new
    assert_empty ItServices::EndpointMaintenance.pending_for!(device: device)
  end

  test "maintenance results reject arbitrary payload keys" do
    assert_raises(ArgumentError) do
      ItServices::EndpointMaintenance.report!(
        device: NetworkManagedDevice.new, action_id: 1, nonce: "fake",
        result: { "status" => "ok", "observation" => "fine", "command" => "shell" })
    end
  end

  test "maintenance results reject invalid status" do
    assert_raises(ArgumentError) do
      ItServices::EndpointMaintenance.report!(
        device: NetworkManagedDevice.new, action_id: 1, nonce: "fake",
        result: { "status" => "verified", "observation" => "fine" })
    end
  end

  test "unsupported remote actions are rejected" do
    assert_raises(ArgumentError) do
      ItServices::EndpointMaintenance.approve!(device: NetworkManagedDevice.new,
        actor: nil, code: "execute_shell")
    end
  end

  test "unapproved actors cannot schedule maintenance" do
    assert_raises(ArgumentError) do
      ItServices::EndpointMaintenance.approve!(device: NetworkManagedDevice.new,
        actor: nil, code: "refresh_inventory")
    end
  end
end
