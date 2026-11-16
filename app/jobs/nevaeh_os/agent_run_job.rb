# frozen_string_literal: true
module NevaehOs
  class AgentRunJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit=true
    def perform(id) = AgentWorkforce.execute!(NevaehAgentRun.find(id))
  end
end
