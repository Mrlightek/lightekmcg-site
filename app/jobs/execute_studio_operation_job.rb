class ExecuteStudioOperationJob < ApplicationJob
  queue_as :studio

  def perform(studio_operation_id)
    operation = StudioOperation.find(studio_operation_id)
    return if operation.terminal?

    operation.update!(status: "running", started_at: Time.current, error_message: nil)
    Studio::Operations::Dispatcher.new(operation).call
    operation.update!(status: "completed", completed_at: Time.current)
  rescue StandardError => error
    operation&.update(
      status: "failed",
      completed_at: Time.current,
      error_message: error.message.to_s.first(2_000)
    )
    raise
  end
end
