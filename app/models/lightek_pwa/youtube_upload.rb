module LightekPwa
  class YoutubeUpload < ApplicationRecord
    self.table_name = 'lightek_pwa_youtube_uploads'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :user
    belongs_to :post, optional: true
    belongs_to :peer, class_name: 'LightekReservations::Peer', optional: true
    has_one_attached :staged_original
    before_validation { self.public_key ||= SecureRandom.uuid }
    validates :public_key, uniqueness: true
    validates :status, inclusion: {in: %w[queued relaying uploading processing ready failed reconciliation_required withdraw_pending withdrawn]}
    validates :byte_size, numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: 250.megabytes}
    validates :content_type, inclusion: {in: %w[video/mp4 video/webm video/quicktime]}
    validates :title, presence: true, length: {maximum: 100}
    validates :description, length: {maximum: 5000}
    def session_slug = "pwa-youtube-session-#{public_key}"
    def summary = {key: public_key, status: status, video_id: status == 'ready' ? video_id : nil, error_code: error_code}
  end
end
