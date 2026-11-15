class NevaehGoal < ApplicationRecord
  belongs_to :user
  has_many :steps,-> {order(:position)},class_name:'NevaehGoalStep',dependent: :restrict_with_error
  validates :title,presence:true,length:{maximum:160}
  validates :request_key,format:{with:/\A[a-zA-Z0-9_-]{8,100}\z/},uniqueness:{scope: :user_id}
  validates :status,inclusion:{in:%w[draft running paused blocked completed cancelled]}
end
