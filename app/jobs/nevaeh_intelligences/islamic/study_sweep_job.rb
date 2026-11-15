# frozen_string_literal: true
module NevaehIntelligences
  module Islamic
    class StudySweepJob < ApplicationJob
      queue_as :default
      def perform = Study.sweep!
    end
  end
end
