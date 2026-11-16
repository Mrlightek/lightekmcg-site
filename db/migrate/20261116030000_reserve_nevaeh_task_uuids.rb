# frozen_string_literal: true
require 'securerandom'

class ReserveNevaehTaskUuids < ActiveRecord::Migration[8.0]
  def up
    add_column :nevaeh_agent_runs, :task_uuid, :string
    # Preserve historical run IDs and journal entries; assign stable identities
    # before requiring reservations for all future worker executions.
    runs = Class.new(ActiveRecord::Base) { self.table_name = 'nevaeh_agent_runs' }
    runs.reset_column_information
    runs.find_each { |run| run.update_columns(task_uuid: SecureRandom.uuid) }
    change_column_null :nevaeh_agent_runs, :task_uuid, false
    add_index :nevaeh_agent_runs, :task_uuid, unique: true
  end

  def down
    remove_column :nevaeh_agent_runs, :task_uuid
  end
end
