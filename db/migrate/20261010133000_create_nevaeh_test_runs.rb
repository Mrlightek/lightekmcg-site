# frozen_string_literal: true
class CreateNevaehTestRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_test_runs do |t|
      t.string :run_id, null: false
      t.string :status, null: false
      t.string :capability_slug
      t.bigint :nevaeh_capability_id
      t.bigint :marlon_ticket_id
      t.string :correlation_id
      t.string :git_sha
      t.string :environment
      t.integer :exit_status
      t.integer :tests_count
      t.integer :assertions_count
      t.integer :failures_count
      t.integer :errors_count
      t.integer :skips_count
      t.decimal :duration_seconds, precision: 12, scale: 3
      t.datetime :started_at
      t.datetime :finished_at
      t.string :output_sha256, null: false
      t.string :report_path, null: false
      t.string :output_path, null: false
      t.jsonb :report, null: false, default: {}
      t.timestamps
    end
    add_index :nevaeh_test_runs, :run_id, unique: true
    add_index :nevaeh_test_runs, [:capability_slug, :created_at]
    add_index :nevaeh_test_runs, :marlon_ticket_id
    add_index :nevaeh_test_runs, :correlation_id
  end
end
