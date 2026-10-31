class ExecuteStudioOperationJob < ApplicationJob
  queue_as :studio

  def perform(studio_operation_id)
    operation = StudioOperation.find(studio_operation_id)
    operation.with_lock do
      return if operation.terminal?
      return unless operation.executable?
      operation.update!(status: "running", started_at: Time.current, error_message: nil)
    end
    Studio::Operations::Dispatcher.new(operation).call
    operation.with_lock do
      operation.update!(status: "completed", completed_at: Time.current) unless operation.status == "cancelled"
    end
  rescue Studio::MediaProcess::Cancelled => error
    operation&.update(status: "cancelled", completed_at: Time.current, error_message: error.message)
  rescue StandardError => error
    cancelled = false
    if operation
      operation.with_lock do
        cancelled = operation.status == "cancelled"
        operation.update!(status: "failed", completed_at: Time.current, error_message: error.message.to_s.first(2_000)) unless cancelled
      end
    end
    raise unless cancelled
  end
end
