class ScheduleItDeviceMaintenanceActions < ActiveRecord::Migration[8.0]
  def change
    add_column :it_device_maintenance_actions, :starts_at, :datetime
    add_index :it_device_maintenance_actions, [:network_managed_device_id, :status, :expires_at],
      name: "index_it_device_actions_on_device_status_expiry"
  end
end
