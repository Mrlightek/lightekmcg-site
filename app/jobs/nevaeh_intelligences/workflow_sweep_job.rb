# frozen_string_literal: true
module NevaehIntelligences
  class WorkflowSweepJob < ApplicationJob
    queue_as :default
    def perform
      WorkflowRunner.tick!
    end
  end
end
