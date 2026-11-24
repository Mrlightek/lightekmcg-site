class AddHealthTelemetryToNetworkManagedDevices < ActiveRecord::Migration[8.0]
  def change
    add_column :network_managed_devices, :health_telemetry, :jsonb, default: {}, null: false
    add_column :network_managed_devices, :health_telemetry_at, :datetime
  end
end
