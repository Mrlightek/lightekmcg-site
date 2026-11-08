# frozen_string_literal: true
module NevaehIntelligences
  module Neural
    class TrainingJob < ApplicationJob
      queue_as :default
      def perform(id)
        Training.run!(NevaehTrainingRun.find(id))
      end
    end
  end
end
