class CreateStudioOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_operations do |t|
      t.references :studio_project, null: false, foreign_key: true
      t.references :production, null: true, foreign_key: true
      t.references :studio_scene, null: true, foreign_key: true
      t.string :operation_type, null: false
      t.string :provider, null: false
      t.string :capability, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :intent, null: false, default: {}
      t.jsonb :manifest, null: false, default: {}
      t.jsonb :cost_quote, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.string :gatekeeper_operation_id
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :studio_operations, :status
    add_index :studio_operations, :operation_type
    add_index :studio_operations, :provider
    add_index :studio_operations, :gatekeeper_operation_id
  end
end
