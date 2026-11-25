# frozen_string_literal: true

class CreateReleaseAssuranceWorkflows < ActiveRecord::Migration[8.0]
  def change
    create_table :release_assurance_workflows do |t|
      t.references :candidate, null: false, foreign_key: { to_table: :release_assurance_candidates }
      t.references :environment, foreign_key: { to_table: :release_assurance_environments }
      t.string :source_sha, null: false
      t.integer :definition_version, null: false
      t.jsonb :steps, null: false
      t.datetime :finished_at
      t.timestamps
      t.index %i[candidate_id environment_id], unique: true, where: "finished_at IS NULL AND environment_id IS NOT NULL",
        name: "idx_release_active_staging_workflow"
      t.index :candidate_id, unique: true, where: "finished_at IS NULL AND environment_id IS NULL",
        name: "idx_release_active_ci_workflow"
    end
  end
end
