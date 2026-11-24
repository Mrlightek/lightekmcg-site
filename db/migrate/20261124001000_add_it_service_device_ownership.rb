class AddItServiceDeviceOwnership < ActiveRecord::Migration[8.0]
  def change
    add_reference :network_managed_devices, :owner, null: true, foreign_key: { to_table: :users }
    add_reference :it_service_requests, :network_managed_device, null: true, foreign_key: true
  end
end
