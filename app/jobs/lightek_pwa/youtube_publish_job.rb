module LightekPwa
  class YoutubePublishJob < ApplicationJob
    class Busy < StandardError; end
    queue_as :default
    retry_on Busy, wait: 30.seconds, attempts: 30
    retry_on ActiveRecord::Deadlocked, YoutubePublishing::Unavailable, YoutubeApi::Unavailable, LightekReservations::Federation::Client::Unavailable, IOError, SystemCallError, Timeout::Error, wait: :polynomially_longer, attempts: 12 do |job, _error|
      upload = YoutubeUpload.find_by(id: job.arguments.first)
      upload&.update!(status: 'reconciliation_required', error_code: upload.withdraw_requested_at ? 'withdrawal_needs_operator_review' : 'publishing_needs_operator_review') unless upload&.status.in?(%w[ready withdrawn])
    end
    def perform(id)
      upload = YoutubeUpload.find_by(id: id)
      return unless upload
      # Session lock spans network calls without rolling durable upload/session
      # receipts back when the final HTTP response is lost.
      connection = ActiveRecord::Base.connection
      lock_key = 9_712_000_000 + Integer(id)
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{lock_key})")
      raise Busy, 'Video is already being processed' unless locked == true || locked == 't'
      begin
        YoutubePublishing.advance!(upload)
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{lock_key})")
      end
      self.class.set(wait: upload.created_at < 1.hour.ago ? 15.minutes : 1.minute).perform_later(upload.id) if %w[queued uploading processing relaying withdraw_pending].include?(upload.reload.status)
    end
  end
end
