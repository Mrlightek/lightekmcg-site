# frozen_string_literal: true
class CreateNevaehControlCenter < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_workflows do |t|
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "draft"
      t.jsonb :sections, null: false, default: []
      t.integer :interval_minutes
      t.datetime :next_run_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :nevaeh_workflows, [:status, :next_run_at]
    create_table :nevaeh_workflow_runs do |t|
      t.references :nevaeh_workflow, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.bigint :ticket_id
      t.string :request_key, null: false
      t.string :status, null: false, default: "queued"
      t.jsonb :snapshot, null: false, default: {}
      t.text :error
      t.timestamps
    end
    add_index :nevaeh_workflow_runs, [:nevaeh_workflow_id, :request_key], unique: true, name: "idx_nevaeh_run_request"
    add_index :nevaeh_workflow_runs, :ticket_id, unique: true
    create_table :nevaeh_inference_models do |t|
      t.string :name, null: false
      t.text :description
      t.jsonb :rules, null: false, default: []
      t.jsonb :examples, null: false, default: []
      t.jsonb :lexicon, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    create_table :nevaeh_writing_profiles do |t|
      t.string :name, null: false
      t.string :format, null: false
      t.string :provider, null: false, default: "rules"
      t.references :inference_model, foreign_key: {to_table: :nevaeh_inference_models}
      t.text :instructions
      t.jsonb :templates, null: false, default: []
      t.jsonb :examples, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    create_table :nevaeh_workspace_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: {unique: true}
      t.jsonb :navigation, null: false, default: []
      t.timestamps
    end
  end
end
