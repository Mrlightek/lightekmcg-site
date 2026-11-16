class NevaehTaskExample < ApplicationRecord
  belongs_to :user
  belongs_to :nevaeh_task_dialogue
  validates :phrase,length:{in:1..2000}
  validates :status,inclusion:{in:%w[active retired]}
  validate { errors.add(:task_key,'is not a supported task') unless NevaehOs::TaskCatalog.keys.include?(task_key) }
  before_update do
    if (changes.keys-%w[status updated_at]).any?
      errors.add(:base,'Reviewed examples are immutable; retire this example and review a new one')
      throw :abort
    end
  end
end
