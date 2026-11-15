# frozen_string_literal: true
class CreateNevaehStudyRoutines < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_study_routines do |t|
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.references :source, null: false, foreign_key: {to_table: :nevaeh_islamic_sources}
      t.references :language_model, foreign_key: {to_table: :nevaeh_language_models}
      t.string :name, null: false
      t.jsonb :daily_times, null: false, default: {}
      t.jsonb :dataset_ids, null: false, default: []
      t.boolean :enabled, null: false, default: false
      t.boolean :training_enabled, null: false, default: false
      t.boolean :auto_activate, null: false, default: true
      t.integer :window_minutes, null: false, default: 15
      t.integer :passages_per_session, null: false, default: 10
      t.integer :training_epochs, null: false, default: 3
      t.bigint :reading_after_id, null: false, default: 0
      t.integer :training_cursor, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.text :last_error
      t.datetime :last_tick_at
      t.timestamps
    end
    create_table :nevaeh_study_sessions do |t|
      t.references :nevaeh_study_routine, null: false, foreign_key: true, index: {name: 'idx_study_session_routine'}
      t.references :nevaeh_training_run, foreign_key: true, index: {name: 'idx_study_session_training'}
      t.date :local_date, null: false
      t.string :slot, null: false
      t.datetime :scheduled_at, null: false
      t.datetime :ends_at, null: false
      t.string :status, null: false, default: 'queued'
      t.jsonb :snapshot, null: false, default: {}
      t.jsonb :reading_evidence, null: false, default: []
      t.jsonb :result, null: false, default: {}
      t.string :lease_token
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error
      t.timestamps
    end
    add_index :nevaeh_study_sessions, [:nevaeh_study_routine_id, :local_date, :slot], unique: true, name: 'idx_study_session_daily_slot'
  end
end
