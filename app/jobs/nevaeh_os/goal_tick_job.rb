module NevaehOs
  class GoalTickJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit=true
    def perform(id) = Goals.tick!(NevaehGoal.find(id))
  end
end
