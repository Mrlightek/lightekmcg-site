# frozen_string_literal: true

class CreateNevaehAgencyOnboarding < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_onboarding_playbooks do |t|
      t.references :operator, null: false, foreign_key: {to_table: :users}
      t.references :parent, foreign_key: {to_table: :nevaeh_onboarding_playbooks}
      t.integer :escalate_after_hours, null: false
      t.string :status, null: false
      t.string :evidence_digest, null: false
      t.jsonb :evaluation, null: false, default: {}
      t.datetime :activated_at
      t.datetime :retired_at
      t.timestamps
      t.index [:operator_id, :evidence_digest], unique: true, name: 'idx_onboarding_playbook_evidence'
      t.index :operator_id, unique: true, where: "status = 'active'", name: 'idx_onboarding_active_playbook'
    end

    create_table :nevaeh_onboarding_cases do |t|
      t.references :operator, null: false, foreign_key: {to_table: :users}
      t.references :trial, null: false, foreign_key: {to_table: :lightek_agency_trials}
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}, index: {unique: true}
      t.references :playbook, foreign_key: {to_table: :nevaeh_onboarding_playbooks}
      t.datetime :paid_at, null: false
      t.datetime :dashboard_at
      t.datetime :mailbox_at
      t.datetime :followed_up_at
      t.datetime :completed_at
      t.datetime :closed_at
      t.datetime :escalated_at
      t.datetime :dashboard_escalated_at
      t.string :blocker
      t.string :evaluation_cohort
      t.timestamps
      t.index [:operator_id, :closed_at], name: 'idx_onboarding_operator_cases'
    end
  end
end
