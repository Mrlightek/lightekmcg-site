class FeatureShowcaseJob < ApplicationJob
  queue_as :studio
  self.enqueue_after_transaction_commit = true
  def perform(id)
    showcase = LightekGrowth::FeatureShowcase.find(id)
    showcase.with_lock do
      return unless showcase.status == 'pending'
      showcase.update!(status: 'running', error: nil)
    end
    LightekGrowth::ShowcaseBuilder.new(actor: showcase.created_by, site: showcase.site).render!(showcase)
  rescue StandardError => error
    showcase&.update!(status: 'failed', error: error.message.to_s.first(2000))
    raise
  end
end
