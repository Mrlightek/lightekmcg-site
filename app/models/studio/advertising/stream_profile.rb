# frozen_string_literal: true

module Studio
  module Advertising
    class StreamProfile < ApplicationRecord
      self.table_name = "studio_ad_stream_profiles"
      belongs_to :site, class_name: "DymondSite::Site"
      belongs_to :channel, class_name: "Studio::Broadcasting::Channel"
      has_secure_token :decision_key, length: 48
      validates :platform, inclusion: { in: %w[web roku] }
      validate do
        errors.add(:channel, "must be a managed channel on this site") unless channel&.managed_playout? && channel.site_id == site_id
        unless DemandSource.https_url?(playback_url) && URI.parse(playback_url).path.end_with?(".m3u8")
          errors.add(:playback_url, "must be an HTTPS HLS playback URL")
        end
      rescue URI::InvalidURIError
        errors.add(:playback_url, "must be an HTTPS HLS playback URL")
      end
    end
  end
end
