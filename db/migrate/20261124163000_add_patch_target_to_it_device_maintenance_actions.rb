class AddPatchTargetToItDeviceMaintenanceActions < ActiveRecord::Migration[8.0]
  def change
    add_column :it_device_maintenance_actions, :patch_target, :string, limit: 256
  end
end
