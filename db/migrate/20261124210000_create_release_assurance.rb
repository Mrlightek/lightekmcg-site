# frozen_string_literal: true

class CreateReleaseAssurance < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :staging_access_expires_at, :datetime

    create_table :release_assurance_candidates do |t|
      t.references :operator, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :profile, null: false
      t.string :publication_key, null: false, index: { unique: true }
      t.jsonb :selectors, null: false, default: []
      t.string :base_sha
      t.jsonb :sources, null: false, default: []
      t.string :source_sha
      t.jsonb :conflicts, null: false, default: []
      t.string :state, null: false, default: "queued"
      t.string :assembly_error
      t.references :promotion_approver, foreign_key: { to_table: :users }
      t.datetime :promotion_approved_at
      t.string :promotion_digest
      t.timestamps
    end

    create_table :release_assurance_environments do |t|
      t.references :candidate, null: false, foreign_key: { to_table: :release_assurance_candidates }, index: true
      t.references :provisioning_request, null: false, foreign_key: true, index: { unique: true }
      t.references :deployment_operation, foreign_key: { to_table: :gatekeeper_operations }
      t.string :hostname, null: false, index: { unique: true }
      t.integer :budget_cents, null: false
      t.datetime :expires_at, null: false, index: true
      t.string :state, null: false, default: "prepared"
      t.string :approval_digest
      t.string :failure
      t.timestamps
    end

    create_table :release_assurance_testers do |t|
      t.references :operator, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :email, null: false
      t.string :platform, null: false
      t.string :device_profile, null: false
      t.datetime :consented_at, null: false
      t.datetime :offboarded_at
      t.timestamps
      t.index %i[operator_id email platform], unique: true, name: "idx_release_tester_identity"
    end

    create_table :release_assurance_assignments do |t|
      t.references :tester, null: false, foreign_key: { to_table: :release_assurance_testers }
      t.references :environment, null: false, foreign_key: { to_table: :release_assurance_environments }
      t.string :scenario, null: false
      t.string :invite_digest, null: false, index: { unique: true }
      t.datetime :expires_at, null: false
      t.datetime :redeemed_at
      t.datetime :account_revoked_at
      t.datetime :revoked_at
      t.timestamps
    end

    create_table :release_assurance_runs do |t|
      t.references :candidate, null: false, foreign_key: { to_table: :release_assurance_candidates }
      t.references :environment, foreign_key: { to_table: :release_assurance_environments }
      t.references :assignment, foreign_key: { to_table: :release_assurance_assignments }
      t.string :check_key, null: false
      t.string :kind, null: false
      t.string :result, null: false
      t.string :source_sha, null: false
      t.string :external_id
      t.jsonb :evidence, null: false, default: {}
      t.timestamps
      t.index %i[candidate_id check_key external_id], unique: true, name: "idx_release_acceptance_receipt"
    end

    create_table :release_assurance_defects do |t|
      t.references :candidate, null: false, foreign_key: { to_table: :release_assurance_candidates }
      t.references :run, null: false, foreign_key: { to_table: :release_assurance_runs }, index: { unique: true }
      t.references :retest, foreign_key: { to_table: :release_assurance_runs }
      t.string :status, null: false, default: "open"
      t.bigint :ticket_id
      t.timestamps
    end
  end
end
