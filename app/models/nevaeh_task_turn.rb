class NevaehTaskTurn < ApplicationRecord
  belongs_to :nevaeh_task_dialogue
  validates :request_key,uniqueness:{scope: :nevaeh_task_dialogue_id}
  before_update { throw :abort }
end
