# frozen_string_literal: true
module NevaehIntelligences
  class ManualLearnJob < ApplicationJob
    queue_as :default
    def perform(id) = Manuals.build!(NevaehManualBuild.find(id))
  end
end
