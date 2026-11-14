# frozen_string_literal: true
module NevaehIntelligences
  module Islamic
    class StudyJob < ApplicationJob
      queue_as :default
      def perform(id) = Study.perform!(id)
    end
  end
end
