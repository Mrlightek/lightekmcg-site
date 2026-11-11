# frozen_string_literal: true
class NevaehWatchEvent < ApplicationRecord
  belongs_to :nevaeh_watcher
  belongs_to :nevaeh_agent_run,optional:true
  validates :event_key,presence:true,uniqueness:{scope: :nevaeh_watcher_id}
  validates :status,inclusion:{in:%w[detected prepared dispatched blocked ignored]}
  def execution_status = nevaeh_agent_run ? nevaeh_agent_run.execution_status : status
end
