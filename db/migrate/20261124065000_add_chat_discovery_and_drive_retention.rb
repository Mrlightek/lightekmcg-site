class AddChatDiscoveryAndDriveRetention < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_discovery_channel_holds do |t|
      t.references :matter, null: false, foreign_key: {to_table: :lightek_mail_matters}, index: false
      t.references :channel, null: false, foreign_key: {to_table: :lightek_team_channels, on_delete: :cascade}
      t.datetime :released_at
      t.timestamps
      t.index %i[matter_id channel_id], unique: true
    end

    add_reference :lightek_mail_discovery_events, :channel,
      foreign_key: {to_table: :lightek_team_channels, on_delete: :nullify}

    add_column :lightek_shared_drives, :revision_retention_days, :integer
    add_check_constraint :lightek_shared_drives,
      "revision_retention_days BETWEEN 1 AND 36500", name: "shared_drive_revision_retention_days"
  end
end
