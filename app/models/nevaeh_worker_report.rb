# frozen_string_literal: true
class NevaehWorkerReport < ApplicationRecord
  belongs_to :user
  belongs_to :nevaeh_os_agent
  belongs_to :nevaeh_agent_run
  has_many :reviews, class_name: 'NevaehWorkerReportReview', dependent: :restrict_with_error
  validates :nevaeh_agent_run_id, uniqueness: true
  validates :status, inclusion: {in: %w[pending completed failed blocked cancelled evidence_unavailable]}
  validates :capability, :site_key, presence: true
  validates :contract_sha256, :receipt_sha256, format: {with: /\A[0-9a-f]{64}\z/}
  validate do
    begin
      NevaehOs::ReportSchema.validate!(structured_result)
      unless structured_result['account_id']==user_id && structured_result['task_id']=="run-#{nevaeh_agent_run_id}" && structured_result['status']==status
        errors.add(:structured_result,'must identify this account, task and execution status')
      end
    rescue ArgumentError => error
      errors.add(:structured_result,error.message)
    end
    run = nevaeh_agent_run
    if run && (run.actor_id != user_id || run.nevaeh_agent_worker.nevaeh_os_agent_id != nevaeh_os_agent_id)
      errors.add(:nevaeh_agent_run, 'must belong to this account and specialist')
    end
  end
end
