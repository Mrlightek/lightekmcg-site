class CreateLightekVoiceCarrierOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_voice_carrier_operations do |t|
      t.references :service, null: false, index: false, foreign_key: { to_table: :lightek_communications_services }
      t.references :operator, null: false, foreign_key: { to_table: :users }
      t.string :operation, null: false
      t.string :did, null: false
      t.string :state, null: false, default: "submitting"
      t.string :carrier_reference
      t.string :carrier_status
      t.timestamps
    end
    add_index :lightek_voice_carrier_operations, [:service_id, :operation], unique: true, name: "idx_voice_carrier_service_operation"
    add_index :lightek_voice_carrier_operations, :did, unique: true,
      where: "operation IN ('order_number', 'port_number')", name: "idx_voice_carrier_assigned_did"
  end
end
