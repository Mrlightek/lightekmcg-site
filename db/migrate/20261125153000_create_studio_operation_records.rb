class CreateStudioOperationRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_operation_records do |t|
      t.references :site, null: false, index: false,
        foreign_key: {to_table: :dymond_site_sites, on_delete: :cascade}
      t.string :operation_id, null: false
      t.string :surface, null: false
      t.integer :version, null: false
      t.jsonb :body, null: false
      t.boolean :published, null: false, default: false
      t.timestamps
    end

    add_index :studio_operation_records, [:site_id, :operation_id, :surface, :version], unique: true,
      name: "idx_studio_operation_records_identity"
    add_check_constraint :studio_operation_records, "version > 0", name: "studio_operation_records_positive_version"
    add_check_constraint :studio_operation_records, "surface IN ('image', 'motion', 'both')",
      name: "studio_operation_records_surface"
  end
end
