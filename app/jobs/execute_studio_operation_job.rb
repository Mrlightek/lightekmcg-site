class ExecuteStudioOperationJob < ApplicationJob
  queue_as do
    operation = StudioOperation.find_by(id: arguments.first)
    operation ? Studio::Compute::Queue.name(operation) : "studio"
  end

  def perform(studio_operation_id)
    operation = StudioOperation.find(studio_operation_id)
    if Studio::Compute::Federation::Dispatch.enabled?(operation) && operation.status == "cancelled"
      Studio::Compute::Federation::Dispatch.cancel!(operation)
      return
    end
    remote_row = StudioRemoteRender.find_by(studio_operation_id: operation.id)
    Studio::Compute::Federation::Broker.authorize!(remote_row.peer) if remote_row
    if Studio::Compute::Queue.economy?(operation)
      if Studio::Compute::Queue.dedicated_for?(operation) && !Studio::Compute::Queue.worker? && !Studio::Compute::Federation::Dispatch.enabled?(operation)
        self.class.set(queue: Studio::Compute::Queue.name(operation), wait: 20.seconds).perform_later(operation.id) if operation.executable?
        return
      end
      lease = Studio::Compute::Lease.claim!(operation)
      return unless lease
      lease.run do
        if Studio::Compute::Federation::Dispatch.enabled?(operation)
          finished = Studio::Compute::Federation::Dispatch.call(operation)
          self.class.set(wait: 20.seconds).perform_later(operation.id) unless finished
        else
          execute(operation)
        end
      end
      return
    end
    started = false
    operation.with_lock do
      return if operation.terminal?
      return unless operation.executable?
      operation.update!(status: "running", started_at: Time.current, error_message: nil)
      started = true
    end
    execute(operation)
  rescue Studio::Compute::Lease::Lost
    # A stale worker cannot fail, complete or publish over a newer attempt.
    nil
  rescue Studio::Compute::CpuProfile::Busy
    operation.with_lock do
      return if operation.terminal? || (lease && !lease.valid?)
      return unless lease || started || operation.executable?
      metadata = if Studio::Compute::Queue.economy?(operation)
        operation.metadata.merge("cpu_render_progress"=>operation.metadata.fetch("cpu_render_progress",{}).merge("profile"=>"cpu_economy","phase"=>"waiting_for_cpu_slot"))
      else
        operation.metadata.merge("workflow_phase" => "waiting_for_blender_worker")
      end
      operation.update!(status: "pending", metadata: metadata)
    end
    self.class.set(wait:20.seconds).perform_later(operation.id)
  rescue Studio::MediaProcess::Cancelled => error
    operation&.with_lock do
      return if lease && !lease.valid?
      operation.update!(status: "cancelled", completed_at: Time.current, error_message: error.message)
    end
    Blender::Runner.new(operation).clear_checkpoints! if operation&.provider=="blender" && Studio::Compute::CpuProfile.economy?(operation.manifest)
  rescue StandardError => error
    cancelled = false
    if operation
      operation.with_lock do
        return if lease && !lease.valid?
        cancelled = operation.status == "cancelled"
        operation.update!(status: "failed", completed_at: Time.current, error_message: error.message.to_s.first(2_000)) unless cancelled
      end
    end
    raise unless cancelled
  ensure
    lease&.release!
  end

  private

  def execute(operation)
    Studio::Compute::Lease.check!
    Studio::Operations::Dispatcher.new(operation).call
    operation.with_lock do
      Studio::Compute::Lease.check!
      operation.update!(status: "completed", completed_at: Time.current) unless operation.status == "cancelled"
    end
    Blender::Runner.new(operation).clear_checkpoints! if operation.provider=="blender" && operation.status == "completed" && Studio::Compute::Queue.economy?(operation)
  end
end
