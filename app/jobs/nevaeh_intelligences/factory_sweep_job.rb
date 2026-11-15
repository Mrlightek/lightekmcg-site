# frozen_string_literal: true
module NevaehIntelligences
  class FactorySweepJob < ApplicationJob
    queue_as :default
    def perform
      Neural::Training.sweep!
      LearningPlans.sweep! if defined?(NevaehLearningPlan) && NevaehLearningPlan.table_exists?
      Manuals.sweep! if defined?(NevaehManualBuild) && NevaehManualBuild.table_exists?
    end
  end
end
