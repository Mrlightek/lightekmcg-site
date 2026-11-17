# frozen_string_literal: true
class Post < ApplicationRecord
  before_destroy :detach_youtube_publication, prepend: true
  def youtube_upload = LightekPwa::YoutubeUpload.find_by(post_id: id)
  def detach_youtube_publication
    return unless defined?(LightekPwa::YoutubePublishing)
    upload = youtube_upload
    return unless upload
    LightekPwa::YoutubePublishing.request_withdrawal!(upload)
    upload.update!(post_id: nil)
  end
  after_commit :sync_youtube_visibility, on: :update
  def withdraw_youtube_publication
    LightekPwa::YoutubePublishing.request_withdrawal!(youtube_upload) if defined?(LightekPwa::YoutubePublishing) && youtube_upload
  end
  def sync_youtube_visibility
    return unless defined?(LightekPwa::YoutubePublishing) && (saved_change_to_visibility? || saved_change_to_audience? || saved_change_to_moderation_state? || saved_change_to_expires_at?)
    withdraw_youtube_publication unless visibility == 'public' && audience == 'everyone' && moderation_state == 'published' && (!expires_at || expires_at.future?)
  end
  after_commit :sync_network_publication
  def sync_network_publication
    LightekPwa::Publications.enqueue!(self) if defined?(LightekPwa::Publications)
  rescue StandardError => error
    Rails.logger.error("[PWA publication sync] post=#{id} #{error.class}")
  end
  MEDIA_TYPES = %w[image/jpeg image/png image/webp image/gif video/mp4 video/webm video/quicktime audio/mpeg audio/mp4 audio/wav audio/x-wav audio/ogg audio/flac].freeze
  KINDS = %w[post article photo story video clip audio live event playlist series].freeze
  has_one_attached :spatial_scene
  has_many_attached :spatial_files
  belongs_to :user
  belongs_to :community, optional: true
  belongs_to :site, class_name: "DymondSite::Site", optional: true
  belongs_to :parent, class_name: "Post", optional: true
  has_many :replies, class_name: "Post", foreign_key: :parent_id, dependent: :destroy
  has_many :engagements, class_name: "LightekCommunity::Engagement", dependent: :destroy
  has_many_attached :media
  validates :kind, inclusion: { in: KINDS }
  validates :visibility, inclusion: { in: %w[public followers community private] }
  validates :title, length: { maximum: 160 }
  validates :content, length: { maximum: 50_000 }
  validate :media_constraints
  validate :has_content
  scope :unexpired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  validates :audience, inclusion: { in: %w[everyone women men] }

  validates :moderation_state, inclusion: {in: %w[published hidden]}

  private

  def has_content
    errors.add(:content, "or media is required") if content.blank? && title.blank? && !media.attached?
  end

  def media_constraints
    errors.add(:media, "cannot exceed 8 files") if media.size > 8
    media.each do |attachment|
      errors.add(:media, "must be an image, video or audio file") unless MEDIA_TYPES.include?(attachment.blob.content_type)
      errors.add(:media, "must be smaller than 250 MB") if attachment.blob.byte_size > 250.megabytes
    end
  end
end
