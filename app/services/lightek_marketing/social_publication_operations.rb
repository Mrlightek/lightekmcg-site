# frozen_string_literal: true
module LightekMarketing
  # Site-scoped operational actions for existing publication records.
  class SocialPublicationOperations
    class Invalid < StandardError; end
    def self.refresh!(post:)
      raise Invalid, "TikTok publication required" unless post.connection.provider == "tiktok"
      raise Invalid, "No provider reference" if post.remote_id.blank?
      TiktokSubmissionLifecycle.refresh!(post: post)
    end
    def self.retry!(post:)
      post.with_lock do
        raise Invalid, "Unknown provider outcomes require manual reconciliation" if post.status == "needs_review"
        raise Invalid, "Only failed publications can be retried" unless post.status == "failed"
        raise Invalid, "Campaign must be ready" unless post.campaign.status == "ready"
        raise Invalid, "Destination is disconnected" unless post.connection.enabled?
        # Never retry a TikTok submission with a remote ID: that could duplicate a
        # video already accepted but incorrectly classified by a stale poll.
        raise Invalid, "Existing provider submission must be reconciled, not uploaded twice" if post.remote_id.present?
        post.update!(status: "pending", error: nil, submission_status: nil)
      end
      SocialDispatch.call!(post: post)
    end
  end
end
