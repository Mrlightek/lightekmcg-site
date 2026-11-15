class StudioCpuLeaseSweepJob < ApplicationJob
  queue_as :default

  def perform
    Studio::Compute::Lease.reconcile!(StudioOperation.all)
  end
end
