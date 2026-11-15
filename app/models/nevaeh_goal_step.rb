class NevaehGoalStep < ApplicationRecord
  belongs_to :nevaeh_goal
  belongs_to :nevaeh_os_agent
  belongs_to :nevaeh_agent_run,optional:true
  validates :status,inclusion:{in:%w[waiting running completed blocked]}
  validates :key,format:{with:/\A[a-z][a-z0-9_]{0,39}\z/},uniqueness:{scope: :nevaeh_goal_id}
  validates :label,presence:true,length:{maximum:160}
  validate do
    errors.add(:nevaeh_os_agent,'belongs to another account') if nevaeh_os_agent && nevaeh_goal && nevaeh_os_agent.user_id!=nevaeh_goal.user_id
    errors.add(:command,'must be bounded') unless command.is_a?(Hash) && command.to_json.bytesize<=16000
  end
end
