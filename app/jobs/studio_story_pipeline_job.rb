# frozen_string_literal: true
class StudioStoryPipelineJob < ApplicationJob
  queue_as :studio
  self.enqueue_after_transaction_commit = true
  def perform(id)
    operation=StudioOperation.where(capability:'studio.direct.story').find(id)
    Studio::Director::StoryPipeline.tick!(operation)
    self.class.set(wait:10.seconds).perform_later(id) unless operation.reload.terminal?
  rescue StandardError => error
    operation&.with_lock { operation.update!(status:'failed',completed_at:Time.current,error_message:error.message.to_s.first(2000)) unless operation.terminal? }
    raise
  end
end
