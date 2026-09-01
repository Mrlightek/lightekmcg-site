# app/jobs/tiktok_publish_job.rb
class TiktokPublishJob < ApplicationJob
  queue_as :default

  def perform(social_account_id, video_url, title)
    account = SocialAccount.find(social_account_id)
    
    # Phase 1: Initialize the upload
    init_res = HTTParty.post(
      "https://tiktokapis.com",
      headers: { 
        "Authorization" => "Bearer #{account.access_token}",
        "Content-Type" => "application/json"
      },
      body: {
        source: "PULL_FROM_URL", # Or FILE_UPLOAD for local files
        video_url: video_url,
        post_mode: "DIRECT_POST",
        media_type: "VIDEO",
        title: title
      }.to_json
    )
    
    # TikTok schedules the file fetch or returns an upload URL based on source type
    # Track the response 'publish_id' to query the status later
  end
end
