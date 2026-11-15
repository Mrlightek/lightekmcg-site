class AddSalesIntakeAndTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_sales_intake_rules do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.string :template_key, null: false
      t.string :section_key, null: false
      t.string :source, null: false, default: 'website'
      t.jsonb :mapping, null: false, default: {}
      t.boolean :enabled, null: false, default: false
      t.datetime :enabled_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_sales_intake_rules, [:site_id, :template_key, :section_key], unique: true, name: 'idx_sales_intake_form'
    create_table :lightek_sales_intake_entries do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :inquiry, foreign_key: {to_table: :website_template_inquiries}
      t.references :lead, foreign_key: {to_table: :lightek_sales_leads}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.references :processed_by, foreign_key: {to_table: :users}
      t.string :origin, null: false
      t.string :origin_key, null: false
      t.string :source, null: false
      t.string :status, null: false, default: 'awaiting_review'
      t.jsonb :payload, null: false, default: {}
      t.jsonb :original, null: false, default: {}
      t.string :error_message
      t.datetime :processed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_sales_intake_entries, [:site_id, :origin_key], unique: true, name: 'idx_sales_intake_origin'
    add_index :lightek_sales_intake_entries, [:site_id, :status, :created_at], name: 'idx_sales_intake_review'
    create_table :lightek_sales_tasks do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :owner, null: false, foreign_key: {to_table: :users}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.references :completed_by, foreign_key: {to_table: :users}
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :source_key, null: false
      t.string :title, null: false
      t.string :status, null: false, default: 'open'
      t.datetime :due_at, null: false
      t.datetime :completed_at
      t.datetime :snoozed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_sales_tasks, [:site_id, :source_key], unique: true, name: 'idx_sales_task_source'
    add_index :lightek_sales_tasks, [:site_id, :owner_id, :status, :due_at], name: 'idx_sales_tasks_due'
    add_index :lightek_sales_tasks, [:record_type, :record_id], name: 'idx_sales_task_relationship'
  end
end
