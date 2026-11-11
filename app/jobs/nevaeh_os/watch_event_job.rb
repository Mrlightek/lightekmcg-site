# frozen_string_literal: true
module NevaehOs
  class WatchEventJob < ApplicationJob
    queue_as :default
    def perform(id) = WatchReaction.process!(NevaehWatchEvent.find(id))
  end
end
