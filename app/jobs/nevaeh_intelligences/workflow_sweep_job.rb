# frozen_string_literal: true
module NevaehIntelligences
  class WorkflowSweepJob < ApplicationJob
    queue_as :default
    def perform
      NevaehOs::Goals.sweep!
      WorkflowRunner.tick!
      NevaehOs::AgentWorkforce.tick!
      NevaehOs::WatchEngine.tick!
    end
  end
end
