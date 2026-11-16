# frozen_string_literal: true
class NevaehAgentRun < ApplicationRecord
  belongs_to :nevaeh_agent_worker
  belongs_to :actor,class_name:'User'
  belongs_to :nevaeh_os_action,optional:true
  validates :status,inclusion:{in:%w[queued dispatched blocked]}
  validates :request_key,presence:true,uniqueness:{scope: :nevaeh_agent_worker_id}
  validates :task_uuid, uniqueness: true, format: {with: /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/}
  validate do
    errors.add(:task_uuid, 'is an immutable manager reservation') if persisted? && will_save_change_to_task_uuid?
  end
  def execution_status
    nevaeh_os_action ? NevaehOs::Receipts.for(nevaeh_os_action)[:status] : status
  end
end
