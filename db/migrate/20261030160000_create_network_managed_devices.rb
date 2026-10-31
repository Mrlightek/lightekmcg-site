class CreateNetworkManagedDevices < ActiveRecord::Migration[8.0]
  def change
    create_table :network_managed_devices do |t|
      t.string :name, null: false
      t.string :device_type, null: false
      t.string :identifier, null: false
      t.string :status, null: false, default: "registered"
      t.string :management_protocol
      t.string :hostname
      t.string :ip_address
      t.string :manufacturer
      t.string :model
      t.string :os_version
      t.text :notes
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :network_managed_devices, :identifier, unique: true
    add_index :network_managed_devices, [:device_type, :status]
  end
end
