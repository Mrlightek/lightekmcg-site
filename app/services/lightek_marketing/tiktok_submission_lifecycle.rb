# frozen_string_literal: true
module LightekMarketing
  # Tracks the provider-reported state. Inbox delivery is not public publication.
  class TiktokSubmissionLifecycle
    STATUSES = %w[PROCESSING_UPLOAD PROCESSING_DOWNLOAD SEND_TO_USER_INBOX PUBLISH_COMPLETE FAILED].freeze
    def self.refresh!(post:)
      post.with_lock do
        raise ArgumentError, "Not a TikTok submission" unless post.connection.provider == "tiktok" && post.remote_id.present?
        raise ArgumentError, "Connection is disabled" unless post.connection.enabled?
        return post if post.status == "published" || post.submission_status == "FAILED"
        data = TiktokVideoUpload.status!(connection: post.connection, publish_id: post.remote_id)
        status = data.fetch("status")
        raise TiktokVideoUpload::Invalid, "Unrecognized TikTok status" unless STATUSES.include?(status)
        attrs = {submission_status: status, last_checked_at: Time.current}
        case status
        when "PUBLISH_COMPLETE"
          attrs.merge!(status: "published", published_at: Time.current)
        when "FAILED"
          attrs.merge!(status: "failed", error: data["fail_reason"].to_s.slice(0, 1000))
        end
        post.update!(attrs)
        post
      end
    end
  end
end
