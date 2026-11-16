# frozen_string_literal: true
class CreateNevaehWorkerReports < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_worker_reports do |t|
      t.references :user, null: false, foreign_key: true
      t.references :nevaeh_os_agent, null: false, foreign_key: true
      t.references :nevaeh_agent_run, null: false, foreign_key: true, index: {unique: true}
      t.string :capability, null: false
      t.string :site_key, null: false
      t.string :contract_sha256, null: false
      t.string :receipt_sha256, null: false
      t.string :status, null: false
      t.jsonb :evidence, null: false, default: {}
      t.timestamps
    end
    add_index :nevaeh_worker_reports, [:user_id, :nevaeh_os_agent_id, :capability, :site_key], name: 'idx_nevaeh_worker_report_context'
    create_table :nevaeh_worker_report_reviews do |t|
      t.references :nevaeh_worker_report, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :verdict, null: false
      t.string :receipt_sha256, null: false
      t.text :lesson, null: false, default: ''
      t.timestamps
    end
  end
end
