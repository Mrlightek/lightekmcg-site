# frozen_string_literal: true
class Post < ApplicationRecord
  MEDIA_TYPES = %w[image/jpeg image/png image/webp image/gif video/mp4 video/webm video/quicktime audio/mpeg audio/mp4 audio/wav audio/x-wav audio/ogg audio/flac].freeze
  KINDS = %w[post article photo story video clip audio live event playlist series].freeze
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
