class CreateItManagedDeviceIncidents < ActiveRecord::Migration[8.0]
  def change
    create_table :it_managed_device_incidents do |t|
      t.references :network_managed_device, null: false, foreign_key: true, index: false
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :finding_code, null: false
      t.string :status, null: false, default: "open"
      t.datetime :first_observed_at, null: false
      t.datetime :last_observed_at, null: false
      t.datetime :resolved_at
      t.integer :observation_count, null: false, default: 1
      t.timestamps
    end
    add_index :it_managed_device_incidents, [:network_managed_device_id, :finding_code, :status],
      name: "idx_it_device_incident_state"
    add_index :it_managed_device_incidents, [:network_managed_device_id, :finding_code],
      unique: true, where: "status = 'open'", name: "idx_unique_open_it_device_finding"
  end
end
