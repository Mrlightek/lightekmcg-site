class CreateStudioLiveOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_live_operations do |t|
      t.references :studio_project, null: false, foreign_key: true
      t.references :production, null: true, foreign_key: true
      t.string :platform, null: false
      t.string :status, null: false, default: "draft"
      t.string :credential_ref
      t.string :show_run_id
      t.string :gatekeeper_operation_id
      t.jsonb :response_policy, null: false, default: {}
      t.jsonb :moderation_policy, null: false, default: {}
      t.jsonb :metrics, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :started_at
      t.datetime :ended_at
      t.text :error_message
      t.timestamps
    end

    add_index :studio_live_operations, :status
    add_index :studio_live_operations, :platform
    add_index :studio_live_operations, :gatekeeper_operation_id
  end
end
