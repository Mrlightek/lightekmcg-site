module Gatekeeper
  module Fleet
    class UpdateJob < ApplicationJob
      queue_as :default
      def perform(target_id)
        Update.call!(GatekeeperUpdateTarget.find(target_id))
      end
    end
  end
end
