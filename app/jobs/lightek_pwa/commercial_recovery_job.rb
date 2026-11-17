module LightekPwa
  # Bounded recovery for a payment/consent saved before an enqueue failure.
  class CommercialRecoveryJob < ApplicationJob
    queue_as :default
    def perform
      CreatorEarning.where(state: %w[held available transfer_pending]).order(:updated_at).limit(100).each { |earning| earning.touch; CreatorSettlementJob.perform_later(earning.id) }
      expired = YoutubeUpload.joins(:post).where(status: 'ready').where('posts.expires_at <= ?', Time.current)
      expired.limit(100).each { |upload| YoutubePublishing.request_withdrawal!(upload) }
      YoutubeUpload.where(status: %w[queued relaying uploading processing withdraw_pending]).order(:updated_at).limit(100).each { |upload| upload.touch; YoutubePublishJob.perform_later(upload.id) }
    end
  end
end
