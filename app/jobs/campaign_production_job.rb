# frozen_string_literal: true
class CampaignProductionJob < ApplicationJob
  queue_as :studio
  self.enqueue_after_transaction_commit = true
  def perform(id)
    operation = StudioOperation.find(id)
    operation.with_lock do
      return unless operation.capability == LightekMarketing::CampaignProducer::CAPABILITY && operation.status == 'pending'
      operation.update!(status: 'running', started_at: Time.current, error_message: nil)
    end
    actor = User.find(operation.intent.fetch('user_id'))
    LightekMarketing::CampaignProducer.find!(id, actor: actor)
    LightekMarketing::CampaignComposition.new(operation, actor).build! unless operation.manifest['timeline']
    Studio::Providers::FfmpegProvider.new(operation.reload).call
    operation.with_lock do
      operation.update!(status: 'completed', completed_at: Time.current) unless operation.status == 'cancelled'
    end
  rescue StandardError => error
    operation&.with_lock do
      operation.update!(status: 'failed', completed_at: Time.current, error_message: error.message.to_s.first(2000)) unless operation.status == 'cancelled'
    end
    raise
  end
end
