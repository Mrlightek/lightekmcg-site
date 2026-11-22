# frozen_string_literal: true

class CreateNevaehResolutionExperiments < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_resolution_playbooks do |t|
      t.references :operator, null: false, foreign_key: {to_table: :users}
      t.references :parent, foreign_key: {to_table: :nevaeh_resolution_playbooks}
      t.string :workflow, null: false
      t.string :strategy, null: false
      t.string :status, null: false
      t.string :evidence_digest, null: false
      t.jsonb :evidence, default: {}, null: false
      t.datetime :activated_at
      t.timestamps
      t.index [:operator_id, :workflow, :evidence_digest], unique: true, name: 'idx_nevaeh_resolution_playbook_evidence'
      t.index [:operator_id, :workflow], unique: true, where: "status IN ('trial', 'active')",
        name: 'idx_nevaeh_resolution_current_playbook'
    end

    create_table :nevaeh_resolution_observations do |t|
      t.references :operator, null: false, foreign_key: {to_table: :users}
      t.references :playbook, foreign_key: {to_table: :nevaeh_resolution_playbooks}
      t.string :workflow, null: false
      t.bigint :subject_id, null: false
      t.string :comparison_key, null: false
      t.string :cohort, null: false
      t.datetime :started_at, null: false
      t.datetime :measured_at
      t.jsonb :signals, default: {}, null: false
      t.jsonb :receipt, default: {}, null: false
      t.jsonb :outcome, default: {}, null: false
      t.timestamps
      t.index [:workflow, :subject_id], unique: true, name: 'idx_nevaeh_resolution_subject'
      t.index [:workflow, :comparison_key], unique: true, name: 'idx_nevaeh_resolution_comparison'
      t.index [:operator_id, :workflow, :measured_at], name: 'idx_nevaeh_resolution_measurements'
    end

    add_column :nevaeh_onboarding_cases, :mailbox_attempts, :integer, default: 0, null: false
    add_column :nevaeh_onboarding_cases, :mailbox_attempted_at, :datetime
  end
end
