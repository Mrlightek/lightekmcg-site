# frozen_string_literal: true
module NevaehOs
  class AgentRunJob < ApplicationJob
    queue_as :default
    def perform(id) = AgentWorkforce.execute!(NevaehAgentRun.find(id))
  end
end
