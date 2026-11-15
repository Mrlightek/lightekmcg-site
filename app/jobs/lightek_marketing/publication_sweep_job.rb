module LightekMarketing
  class PublicationSweepJob < ApplicationJob
    queue_as :default
    def perform
      PublicationSlot.where(status: 'scheduled').where('scheduled_at <= ?', Time.current).where('queue_requested_at IS NULL OR queue_requested_at < ?', 5.minutes.ago).order(:scheduled_at).limit(100).each do |slot|
        slot.with_lock do
          next unless slot.status == 'scheduled' && (!slot.queue_requested_at || slot.queue_requested_at < 5.minutes.ago)
          slot.update!(queue_requested_at: Time.current)
          PublicationSlotJob.perform_later(slot.id)
        end
      end
      PublicationSlot.left_joins(:social_post).where(status: %w[dispatching submitted needs_review]).where(
        "lightek_marketing_social_posts.status = 'published' OR (lightek_marketing_publication_slots.status = 'submitted' AND lightek_marketing_social_posts.status IN ('failed', 'needs_review')) OR (lightek_marketing_publication_slots.status = 'dispatching' AND lightek_marketing_publication_slots.started_at < ?)", 15.minutes.ago).includes(:social_post).order(:id).limit(200).each do |slot|
        slot.with_lock do
          post = slot.social_post&.reload
          if post&.status == 'published'
            slot.update!(status: 'published', finished_at: Time.current, error_message: nil)
          elsif post&.remote_id.present? && slot.status == 'dispatching'
            slot.update!(status: 'submitted', finished_at: Time.current)
          elsif slot.status == 'dispatching' && slot.started_at && slot.started_at < 15.minutes.ago
            post&.with_lock do
              post.update!(status: 'needs_review', error: 'Calendar submission lease expired; reconcile provider history.') if post.status == 'pending' && post.remote_id.blank?
            end
            if post&.status == 'published'
              slot.update!(status: 'published', finished_at: Time.current, error_message: nil)
            elsif post&.remote_id.present?
              slot.update!(status: 'submitted', finished_at: Time.current)
            else
              slot.update!(status: 'needs_review', error_message: 'Submission lease expired. Check provider history before any manual retry.', finished_at: Time.current)
            end
          elsif slot.status == 'submitted' && post&.status.in?(%w[failed needs_review])
            slot.update!(status: 'needs_review', error_message: 'Provider submission needs reconciliation. Inspect its publication record.')
          end
        end
      end
    end
  end
end
