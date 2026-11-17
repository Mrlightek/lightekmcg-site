module LightekPwa
  # Bounded recovery for a payment/consent saved before an enqueue failure.
  class CommercialRecoveryJob < ApplicationJob
    queue_as :default
    def perform
      SharedPool.where(status: 'provisioning').where.not(launch_id: nil).where('updated_at < ?', 10.minutes.ago).limit(5).each { |row| row.touch; MemberPoolJob.perform_later(row.id) }
      MemberSignupRequest.where(state: 'queued').order(:updated_at).limit(100).each { |row| row.touch; MemberSignupJob.perform_later(row.site_id, row.user_id) }
      MemberBackend.where(status: %w[queued provisioning]).where('updated_at < ?', 10.minutes.ago).limit(25).each { |row| row.touch; MemberBackendJob.perform_later(row.id) }
      MemberBackend.where(status: 'migrating').or(MemberBackend.where(status: 'dedicated_ready').where("migration_receipt ->> 'state' = ?", 'committed')).where('updated_at < ?', 10.minutes.ago).limit(25).each { |row| row.touch; BackendMigrationJob.perform_later(row.id) }
      MemberTicket.where('expires_at < ?', 1.day.ago).delete_all
      CreatorEarning.where(state: %w[held available transfer_pending]).order(:updated_at).limit(100).each { |earning| earning.touch; CreatorSettlementJob.perform_later(earning.id) }
      expired = YoutubeUpload.joins(:post).where(status: 'ready').where('posts.expires_at <= ?', Time.current)
      expired.limit(100).each { |upload| YoutubePublishing.request_withdrawal!(upload) }
      YoutubeUpload.where(status: %w[queued relaying uploading processing withdraw_pending]).order(:updated_at).limit(100).each { |upload| upload.touch; YoutubePublishJob.perform_later(upload.id) }
    end
  end
end
