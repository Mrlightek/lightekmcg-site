class AddDiscoveryDriveHolds < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_discovery_drive_holds do |t|
      t.references :matter, null: false, index: false, foreign_key: {to_table: :lightek_mail_matters}
      t.references :drive, null: false, foreign_key: {to_table: :lightek_shared_drives}
      t.datetime :released_at
      t.timestamps
      t.index %i[matter_id drive_id], unique: true
    end

    add_reference :lightek_mail_discovery_events, :drive,
      foreign_key: {to_table: :lightek_shared_drives, on_delete: :nullify}
  end
end
