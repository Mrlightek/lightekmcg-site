# frozen_string_literal: true
class NevaehAgentRun < ApplicationRecord
  belongs_to :nevaeh_agent_worker
  belongs_to :actor,class_name:'User'
  belongs_to :nevaeh_os_action,optional:true
  validates :status,inclusion:{in:%w[queued dispatched blocked]}
  validates :request_key,presence:true,uniqueness:{scope: :nevaeh_agent_worker_id}
  def execution_status
    nevaeh_os_action ? NevaehOs::Receipts.for(nevaeh_os_action)[:status] : status
  end
end
