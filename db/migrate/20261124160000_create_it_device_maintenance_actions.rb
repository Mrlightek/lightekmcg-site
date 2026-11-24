class CreateItDeviceMaintenanceActions < ActiveRecord::Migration[8.0]
  def change
    create_table :it_device_maintenance_actions do |t|
      t.references :network_managed_device, null: false, foreign_key: true
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.references :approved_by, null: false, foreign_key: { to_table: :users }
      t.string :action_code, null: false
      t.string :status, null: false, default: "approved"
      t.string :request_nonce, null: false
      t.datetime :expires_at, null: false
      t.datetime :reported_at
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end
    add_index :it_device_maintenance_actions, :request_nonce, unique: true
  end
end
