# frozen_string_literal: true
class CreateNevaehManualLearning < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_manual_builds do |t|
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.string :name, null: false
      t.string :status, null: false, default: 'queued'
      t.jsonb :manifest, null: false, default: []
      t.jsonb :dataset_ids, null: false, default: []
      t.jsonb :coverage, null: false, default: {}
      t.text :error
      t.timestamps
    end
    create_table :nevaeh_language_bindings do |t|
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.references :nevaeh_manual_build, foreign_key: true, index: {name: 'idx_language_binding_build'}
      t.string :name, null: false
      t.string :status, null: false, default: 'draft'
      t.jsonb :patterns, null: false, default: []
      t.jsonb :slots, null: false, default: {}
      t.jsonb :command_template, null: false, default: {}
      t.jsonb :source_refs, null: false, default: []
      t.string :contract_sha256
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    create_table :nevaeh_learning_plans do |t|
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.references :language_model, null: false, foreign_key: {to_table: :nevaeh_language_models}
      t.references :active_training_run, foreign_key: {to_table: :nevaeh_training_runs}
      t.references :nevaeh_manual_build, foreign_key: true, index: {name: 'idx_learning_plan_build'}
      t.string :name, null: false
      t.jsonb :dataset_ids, null: false, default: []
      t.integer :position, null: false, default: 0
      t.integer :attempt, null: false, default: 0
      t.integer :epochs, null: false, default: 3
      t.string :status, null: false, default: 'paused'
      t.text :error
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
  end
end
