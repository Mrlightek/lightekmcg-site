# app/jobs/instagram_publish_job.rb
class InstagramPublishJob < ApplicationJob
  queue_as :default

  def perform(social_account_id, media_url, caption)
    account = SocialAccount.find(social_account_id) # Holds access_token and ig_user_id
    token = account.access_token
    ig_id = account.instagram_business_id

    # Phase 1: Create a media container
    container_res = HTTParty.post(
      "https://facebook.com{ig_id}/media",
      query: { image_url: media_url, caption: caption, access_token: token }
    )
    container_id = container_res.parsed_response["id"]

    # (Optional but recommended: sleep or polling block here for processing status)

    # Phase 2: Publish the media container
    HTTParty.post(
      "https://facebook.com{ig_id}/media_publish",
      query: { creation_id: container_id, access_token: token }
    )
  end
end
