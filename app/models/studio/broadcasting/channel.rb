# frozen_string_literal: true
require "uri"
module Studio
  module Broadcasting
    class Channel < ApplicationRecord
      self.table_name = "studio_broadcast_channels"
      belongs_to :site, class_name: "DymondSite::Site"
      has_many :programs, class_name: "Studio::Broadcasting::Program", dependent: :destroy
      validates :name, presence: true, length: {maximum: 120}
      validates :description, length: {maximum: 2000}
      validates :status, inclusion: {in: %w[draft published off_air]}
      validates :position, numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than: 10000}
      validate :public_urls
      private
      def public_urls
        %w[playback_url image_url].each do |field|
          next if self[field].blank?
          uri = URI.parse(self[field]) rescue nil
          errors.add(field, "must be a public HTTPS URL") unless uri && uri.scheme == "https" && uri.host.present? && !uri.userinfo && !uri.fragment && !uri.query.to_s.match?(/(?:stream_key|token|secret)=/i)
        end
        errors.add(:playback_url, "is required before going on air") if status == "published" && playback_url.blank?
        if playback_url.present?
          path = (URI.parse(playback_url).path rescue "")
          errors.add(:playback_url, "must point to an HLS playlist or MP4") unless path.match?(/\.(?:m3u8|mp4)\z/i)
        end
      end
    end
  end
end
