# frozen_string_literal: true
module LightekMarketing
  class TiktokSubmissionPollJob < ApplicationJob
    queue_as :default
    retry_on TiktokVideoUpload::Invalid, LightekVault::Service::AccessDenied, wait: :polynomially_longer, attempts: 5
    def perform(post_id, attempt = 0)
      post = SocialPost.find(post_id)
      return if post.status.in?(%w[published failed]) || post.remote_id.blank?
      TiktokSubmissionLifecycle.refresh!(post: post)
      return if post.reload.status.in?(%w[published failed])
      # Inbox submission can remain pending until the creator opens TikTok.
      return if attempt >= 11
      self.class.set(wait: 15.minutes).perform_later(post.id, attempt + 1)
    end
  end
end
