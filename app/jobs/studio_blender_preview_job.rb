class StudioBlenderPreviewJob < ApplicationJob
  queue_as :studio
  def perform(id)
    operation=StudioOperation.find(id)
    operation.with_lock do
      return unless operation.status=="pending"
      raise ArgumentError,"Not an authoring preview" unless operation.capability=="studio.workspace.blender.preview" && operation.metadata["draft_preview"]
      operation.update!(status:"running")
    end
    Studio::Providers::BlenderProvider.new(operation).call
    operation.update!(status:"completed")
  rescue StandardError=>error
    operation&.update!(status:"failed",error_message:error.message.to_s.first(1000))
    raise
  end
end
