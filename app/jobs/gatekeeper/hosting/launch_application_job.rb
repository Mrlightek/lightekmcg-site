module Gatekeeper
  module Hosting
    class LaunchApplicationJob < ApplicationJob
      queue_as :default
      def perform(id) = Launches.perform!(GatekeeperApplicationLaunch.find(id))
    end
  end
end
