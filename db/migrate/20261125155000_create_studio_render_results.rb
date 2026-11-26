class CreateStudioRenderResults < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_render_results do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites, on_delete: :cascade}
      t.references :user, null: false, foreign_key: {on_delete: :cascade}
      t.references :operation_record, foreign_key: {to_table: :studio_operation_records, on_delete: :nullify}
      t.string :operation_id, null: false
      t.string :surface, null: false
      t.integer :version, null: false
      t.string :input_filename
      t.string :status, default: "pending", null: false
      t.jsonb :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :studio_render_results, [:site_id, :user_id, :operation_id, :surface, :created_at],
      name: "index_studio_render_results_on_run_history"
    add_check_constraint :studio_render_results, "status IN ('pending', 'running', 'completed', 'failed')",
      name: "studio_render_results_status_check"
  end
end
