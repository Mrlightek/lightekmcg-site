# frozen_string_literal: true
require 'securerandom'

class ReserveNevaehTaskUuids < ActiveRecord::Migration[8.0]
  def up
    add_column :nevaeh_agent_runs, :task_uuid, :string
    # One-time UUIDv4 assignment: run.id remains the permanent legacy run-N
    # mapping key. Never derive or regenerate an existing reservation. The
    # follow-up BackfillNevaehReportReferences maps reports and dependencies.
    runs = Class.new(ActiveRecord::Base) { self.table_name = 'nevaeh_agent_runs' }
    runs.reset_column_information
    runs.where(task_uuid:nil).find_each { |run| run.update_columns(task_uuid: SecureRandom.uuid) }
    change_column_null :nevaeh_agent_runs, :task_uuid, false
    add_index :nevaeh_agent_runs, :task_uuid, unique: true
  end

  def down
    remove_column :nevaeh_agent_runs, :task_uuid
  end
end
