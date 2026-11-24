class AddAutomaticVoiceFulfillment < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_voice_add_ons, :setup_secret_slug, :string
    add_column :lightek_voice_add_ons, :fulfillment_status, :string
    change_column_null :lightek_voice_carrier_operations, :operator_id, true
    change_column_null :lightek_communications_service_events, :operator_id, true
  end
end
