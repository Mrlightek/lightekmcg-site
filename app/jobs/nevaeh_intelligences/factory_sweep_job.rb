# frozen_string_literal: true
module NevaehIntelligences
  class FactorySweepJob < ApplicationJob
    queue_as :default
    def perform = Neural::Training.sweep!
  end
end
