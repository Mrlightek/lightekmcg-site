class NevaehTaskDialogue < ApplicationRecord
  belongs_to :user
  belongs_to :nevaeh_os_action,optional:true
  belongs_to :nevaeh_goal,optional:true
  has_many :turns,class_name:'NevaehTaskTurn',dependent: :restrict_with_error
  validates :request_key,uniqueness:{scope: :user_id}
  validates :status,inclusion:{in:%w[collecting ready dispatched cancelled]}
  validates :request_text,length:{in:1..4000}
  validate do
    valid=plan.is_a?(Array) && plan.size.between?(1,12) && plan.to_json.bytesize<=24000
    valid &&= plan.all? do |step|
      step.is_a?(Hash) && step.keys.sort==%w[choices inputs phrase task] && step['phrase'].is_a?(String) && step['phrase'].length.between?(1,4000) &&
        step['choices'].is_a?(Array) && step['choices'].size.between?(1,10) && (step['choices']-NevaehOs::TaskCatalog.keys).empty? &&
        (step['task'] ? NevaehOs::TaskCatalog.validate!(step['task'],step['inputs'],partial:true).is_a?(Array) : step['inputs']=={})
    end
    errors.add(:plan,'must contain at most twelve bounded supported tasks') unless valid
  rescue ArgumentError
    errors.add(:plan,'contains invalid task inputs')
  end
  before_update do
    if status_in_database=='dispatched' && (changes.keys-%w[updated_at lock_version]).any?
      errors.add(:base,'Dispatched task inputs and receipts are immutable; start a fresh request')
      throw :abort
    end
  end
end
