class CreateLightekVoiceAddOns < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_voice_add_ons do |t|
      t.references :peer, null: false, index: { unique: true }, foreign_key: { to_table: :lightek_reservation_peers }
      t.references :order, null: false, index: { unique: true }, foreign_key: { to_table: :lightek_commerce_orders }
      t.timestamps
    end
  end
end
