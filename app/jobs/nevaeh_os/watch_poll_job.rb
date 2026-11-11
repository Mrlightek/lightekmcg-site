# frozen_string_literal: true
module NevaehOs
  class WatchPollJob < ApplicationJob
    queue_as :default
    def perform(id,force=false) = WatchEngine.poll!(id,force:force)
  end
end
