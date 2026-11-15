class ExecuteStudioOperationJob < ApplicationJob
  queue_as do
    operation = StudioOperation.find_by(id: arguments.first)
    operation ? Studio::Compute::Queue.name(operation) : "studio"
  end

  def perform(studio_operation_id)
    operation = StudioOperation.find(studio_operation_id)
    if Studio::Compute::Queue.economy?(operation)
      if Studio::Compute::Queue.dedicated? && !Studio::Compute::Queue.worker?
        self.class.set(queue: Studio::Compute::Queue.name(operation), wait: 20.seconds).perform_later(operation.id) if operation.executable?
        return
      end
      lease = Studio::Compute::Lease.claim!(operation)
      return unless lease
      lease.run { execute(operation) }
      return
    end
    operation.with_lock do
      return if operation.terminal?
      return unless operation.executable?
      operation.update!(status: "running", started_at: Time.current, error_message: nil)
    end
    execute(operation)
  rescue Studio::Compute::Lease::Lost
    # A stale worker cannot fail, complete or publish over a newer attempt.
    nil
  rescue Studio::Compute::CpuProfile::Busy
    operation.with_lock do
      return if operation.terminal? || (lease && !lease.valid?)
      return if !lease && !operation.executable?
      operation.update!(status:"pending",metadata:operation.metadata.merge("cpu_render_progress"=>operation.metadata.fetch("cpu_render_progress",{}).merge("profile"=>"cpu_economy","phase"=>"waiting_for_cpu_slot")))
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
    Blender::Runner.new(operation).clear_checkpoints! if operation.status == "completed" && Studio::Compute::Queue.economy?(operation)
  end
end
