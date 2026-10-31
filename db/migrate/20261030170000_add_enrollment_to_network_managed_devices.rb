class AddEnrollmentToNetworkManagedDevices < ActiveRecord::Migration[8.0]
  def change
    add_column :network_managed_devices, :enrollment_token_digest, :string
    add_column :network_managed_devices, :enrolled_at, :datetime
    add_column :network_managed_devices, :last_seen_at, :datetime
    add_column :network_managed_devices, :last_heartbeat_ip, :string
    add_index :network_managed_devices, :enrollment_token_digest, unique: true
  end
end
