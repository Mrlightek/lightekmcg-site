module Gatekeeper
  module Hosting
    class ProvisionApplicationJob < ApplicationJob
      queue_as :default
      def perform(id) = Applications.provision!(GatekeeperHostedApplication.find(id))
    end
  end
end
