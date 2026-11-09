# frozen_string_literal: true
class NevaehAgentWorker < ApplicationRecord
  belongs_to :user
  belongs_to :nevaeh_os_agent
  has_many :runs,class_name:'NevaehAgentRun',dependent: :restrict_with_error
  validates :name,presence:true,length:{maximum:160}
  validates :interval_minutes,numericality:{only_integer:true,greater_than_or_equal_to:5,less_than_or_equal_to:525600},allow_nil:true
  validate do
    errors.add(:nevaeh_os_agent,'belongs to another account') if nevaeh_os_agent && nevaeh_os_agent.user_id != user_id
    errors.add(:command,'must be a bounded executable command') unless command.is_a?(Hash) && command.to_json.bytesize <= 16000 && %w[capability console ubuntu application resource run worker_status project ticket build activate approve train checkpoint write model learn review forget].include?(command['kind'])
  end
  before_save do
    if !enabled? || !interval_minutes
      self.next_run_at=nil
    elsif next_run_at.nil? || will_save_change_to_interval_minutes? || will_save_change_to_enabled?
      self.next_run_at=Time.current+interval_minutes.minutes
    end
  end
end
