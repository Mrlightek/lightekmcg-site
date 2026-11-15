class AddLifecycleControls < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :access_suspended_at, :datetime
    add_column :users, :access_suspension_source, :string
    create_table :lightek_people_lifecycle_cases do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.references :subject, polymorphic: true, null: false
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.references :revoked_by, foreign_key: {to_table: :users}
      t.references :completed_by, foreign_key: {to_table: :users}
      t.string :kind, null: false
      t.string :status, null: false, default: 'open'
      t.jsonb :steps, null: false, default: {}
      t.jsonb :receipt, null: false, default: {}
      t.datetime :access_revoked_at
      t.datetime :completed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_people_lifecycle_cases, [:employer_id, :subject_type, :subject_id], unique: true,
      where: "status NOT IN ('completed', 'canceled')", name: 'idx_open_lifecycle_case'
  end
end
