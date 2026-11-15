class StudioBlenderPreviewJob < ApplicationJob
  queue_as :studio
  def perform(id)
    operation=StudioOperation.find(id)
    operation.with_lock do
      return unless operation.status=="pending"
      raise ArgumentError,"Not an authoring preview" unless %w[studio.workspace.blender.preview studio.workspace.blender.authoring.preview studio.workspace.performance.preview].include?(operation.capability) && operation.metadata["draft_preview"]
      operation.update!(status:"running")
    end
    Studio::Providers::BlenderProvider.new(operation).call
    operation.update!(status:"completed")
    Blender::Runner.new(operation).clear_checkpoints! if Studio::Compute::CpuProfile.economy?(operation.manifest)
  rescue Studio::Compute::CpuProfile::Busy
    operation.with_lock do
      return if operation.status=="cancelled"
      operation.update!(status:"pending")
    end
    self.class.set(wait:20.seconds).perform_later(operation.id)
  rescue StandardError=>error
    operation&.update!(status:"failed",error_message:error.message.to_s.first(1000))
    raise
  end
end
