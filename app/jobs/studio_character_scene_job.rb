class StudioCharacterSceneJob < ApplicationJob
  queue_as :studio
  def perform(id)
    operation=StudioOperation.where(capability:Studio::Performance::CharacterScene::CAPABILITY).find(id)
    operation.with_lock do
      if %w[pending running].include?(operation.status) && Time.iso8601(operation.metadata.fetch("deadline"))<Time.current
        operation.update!(status:"failed",error_message:"Character preparation was interrupted. Retry the saved preparation.",completed_at:Time.current)
      end
      return unless operation.status=="pending"
      operation.update!(status:"running",started_at:Time.current)
    end
    self.class.set(wait:11.minutes).perform_later(id)
    Studio::Performance::CharacterScene.prepare(operation)
  rescue Studio::Performance::CharacterScene::Waiting
    operation.update!(status:"pending") unless operation.reload.status=="cancelled"
    self.class.set(wait:5.seconds).perform_later(id) if operation.status=="pending"
  rescue StandardError=>error
    operation&.with_lock { operation.update!(status:"failed",error_message:error.message.to_s.first(800),completed_at:Time.current) unless operation.status=="cancelled" }
    raise
  end
end
