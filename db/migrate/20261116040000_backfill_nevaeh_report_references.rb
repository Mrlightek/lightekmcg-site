# frozen_string_literal: true
class BackfillNevaehReportReferences < ActiveRecord::Migration[8.0]
  def up
    # Policy: one-time UUIDv4 assignment, never derived or reassigned. The prior
    # migration committed run.id -> task_uuid; reuse that permanent mapping for
    # every historical dependency and queued snapshot. Keep run-N journal lines
    # as audit history and append mapped v2 entries, never rewrite old evidence.
    NevaehAgentRun.reset_column_information
    raise 'Apply ReserveNevaehTaskUuids first' if NevaehAgentRun.where(task_uuid:nil).exists?
    NevaehOs::LegacyReportBackfill.run!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Preserve UUID mappings and append-only report history'
  end
end
