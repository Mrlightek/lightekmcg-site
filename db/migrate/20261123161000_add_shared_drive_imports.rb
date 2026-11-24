class AddSharedDriveImports < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_shared_drive_imports do |t|
      t.references :drive, null: false, foreign_key: {to_table: :lightek_shared_drives}
      t.references :folder, foreign_key: {to_table: :lightek_shared_drive_entries}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.string :filename, null: false
      t.string :state, null: false, default: "preview"
      t.string :run_token
      t.jsonb :items, null: false, default: []
      t.string :error_message
      t.timestamps
    end
    create_table :lightek_shared_drive_import_receipts do |t|
      t.references :drive, null: false, foreign_key: {to_table: :lightek_shared_drives}
      t.references :entry, foreign_key: {to_table: :lightek_shared_drive_entries, on_delete: :nullify}
      t.string :source_key, null: false, limit: 64
      t.string :digest, null: false, limit: 64
      t.timestamps
      t.index %i[drive_id source_key], unique: true, name: "idx_drive_import_receipt_source"
    end
  end
end
