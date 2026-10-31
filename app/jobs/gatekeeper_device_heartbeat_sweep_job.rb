# frozen_string_literal: true

class GatekeeperDeviceHeartbeatSweepJob < ApplicationJob
  queue_as :default

  def perform
    NetworkManagedDevice.stale_heartbeats.find_each do |device|
      device.mark_offline_if_stale!
    end
  end
end
