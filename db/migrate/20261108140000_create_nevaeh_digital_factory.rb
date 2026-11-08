# frozen_string_literal: true
class CreateNevaehDigitalFactory < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_constructions do |t|
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.string :name, null: false
      t.string :key, null: false
      t.text :description
      t.jsonb :definition, null: false, default: {}
      t.jsonb :sample_tests, null: false, default: []
      t.string :status, null: false, default: 'draft'
      t.bigint :active_release_id
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :nevaeh_constructions, :key, unique: true
    create_table :nevaeh_construction_releases do |t|
      t.references :nevaeh_construction, null: false, foreign_key: true, index: {name: 'idx_construction_release_parent'}
      t.integer :version, null: false
      t.jsonb :definition, null: false, default: {}
      t.jsonb :sample_tests, null: false, default: []
      t.jsonb :artifacts, null: false, default: {}
      t.jsonb :verification, null: false, default: {}
      t.string :fingerprint, null: false
      t.string :status, null: false, default: 'built'
      t.timestamps
    end
    add_index :nevaeh_construction_releases, [:nevaeh_construction_id, :version], unique: true, name: 'idx_construction_release_version'
    add_foreign_key :nevaeh_constructions, :nevaeh_construction_releases, column: :active_release_id
    create_table :nevaeh_training_datasets do |t|
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.string :name, null: false
      t.string :status, null: false, default: 'draft'
      t.jsonb :examples, null: false, default: []
      t.jsonb :provenance, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    create_table :nevaeh_language_models do |t|
      t.string :name, null: false
      t.text :description
      t.bigint :active_checkpoint_id
      t.string :visibility, null: false, default: 'internal'
      t.integer :hidden_size, null: false, default: 16
      t.integer :vocabulary_limit, null: false, default: 256
      t.boolean :enabled, null: false, default: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    create_table :nevaeh_training_runs do |t|
      t.references :nevaeh_language_model, null: false, foreign_key: true, index: {name: 'idx_training_run_model'}
      t.references :nevaeh_training_dataset, null: false, foreign_key: true, index: {name: 'idx_training_run_dataset'}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.string :status, null: false, default: 'queued'
      t.string :request_key, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.jsonb :metrics, null: false, default: {}
      t.text :error
      t.datetime :started_at
      t.datetime :heartbeat_at
      t.string :lease_token
      t.integer :epochs, null: false, default: 10
      t.timestamps
    end
    add_index :nevaeh_training_runs, [:nevaeh_language_model_id, :request_key], unique: true, name: 'idx_training_run_request'
    add_index :nevaeh_training_runs, :status, unique: true, where: "status = 'running'", name: 'idx_single_neural_training_lease'
    create_table :nevaeh_language_checkpoints do |t|
      t.references :nevaeh_training_run, null: false, foreign_key: true, index: {unique: true, name: 'idx_checkpoint_run'}
      t.references :nevaeh_language_model, null: false, foreign_key: true, index: {name: 'idx_checkpoint_model'}
      t.jsonb :weights, null: false, default: {}
      t.jsonb :metrics, null: false, default: {}
      t.string :sha256, null: false
      t.string :status, null: false, default: 'candidate'
      t.timestamps
    end
    add_foreign_key :nevaeh_language_models, :nevaeh_language_checkpoints, column: :active_checkpoint_id
    add_reference :nevaeh_writing_profiles, :language_model, foreign_key: {to_table: :nevaeh_language_models}
    create_table :nevaeh_conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :nevaeh_language_model, null: false, foreign_key: true, index: {name: 'idx_conversation_model'}
      t.string :title, null: false, default: 'Conversation'
      t.timestamps
    end
    create_table :nevaeh_conversation_turns do |t|
      t.references :nevaeh_conversation, null: false, foreign_key: true, index: {name: 'idx_turn_conversation'}
      t.string :request_key, null: false
      t.text :prompt, null: false
      t.text :response, null: false
      t.bigint :checkpoint_id, null: false
      t.jsonb :evidence, null: false, default: {}
      t.timestamps
    end
    add_index :nevaeh_conversation_turns, [:nevaeh_conversation_id, :request_key], unique: true, name: 'idx_conversation_request'
  end
end
