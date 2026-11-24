class GateItDeviceBackupRecovery < ActiveRecord::Migration[8.0]
  def change
    add_column :it_device_maintenance_actions, :expected_recovery_digest, :string, limit: 64
    add_column :it_device_maintenance_actions, :owner_consented_at, :datetime
    add_column :it_device_maintenance_actions, :claimed_at, :datetime
  end
end
