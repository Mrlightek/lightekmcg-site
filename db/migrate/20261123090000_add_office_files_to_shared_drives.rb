class AddOfficeFilesToSharedDrives < ActiveRecord::Migration[8.0]
  def change
    add_reference :lightek_office_files, :drive_entry, index: {unique: true},
      foreign_key: {to_table: :lightek_shared_drive_entries}
    change_column_null :lightek_office_files, :channel_id, true
    add_check_constraint :lightek_office_files,
      '(channel_id IS NULL) <> (drive_entry_id IS NULL)', name: 'office_files_have_one_location'
  end
end
