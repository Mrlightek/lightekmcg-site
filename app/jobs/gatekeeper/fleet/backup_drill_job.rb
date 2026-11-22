# frozen_string_literal: true

module Gatekeeper
  module Fleet
    class BackupDrillJob < ApplicationJob
      queue_as :default

      def perform(operation_id)
        operation = GatekeeperOperation.where(capability: BackupDrill::CAPABILITY).find(operation_id)
        BackupDrill.perform!(operation)
      end
    end
  end
end
