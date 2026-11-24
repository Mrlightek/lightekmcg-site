class AddManagedMonitoringConsentToNetworkManagedDevices < ActiveRecord::Migration[8.0]
  def change
    add_column :network_managed_devices, :managed_monitoring_enabled, :boolean, default: false, null: false
    add_index :network_managed_devices, [:managed_monitoring_enabled, :id],
      name: "idx_managed_devices_monitoring"
  end
end
