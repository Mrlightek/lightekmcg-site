# frozen_string_literal: true
class Community < ApplicationRecord
  SECTIONS = %w[featured live conversations clips events members playlists about].freeze
  belongs_to :owner_profile, class_name: "Profile"
  belongs_to :site, class_name: "DymondSite::Site", optional: true
  has_many :memberships, class_name: "LightekCommunity::Membership", dependent: :destroy
  has_many :members, through: :memberships, source: :profile
  has_many :posts, dependent: :destroy
  has_one_attached :cover
  validate :valid_cover
  validates :name, presence: true, length: { maximum: 120 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }, length: { maximum: 160 }
  validates :description, length: { maximum: 10_000 }
  validates :visibility, inclusion: { in: %w[public private] }
  validate :valid_sections

  def member?(profile)
    profile && (owner_profile_id == profile.id || memberships.exists?(profile_id: profile.id))
  end

  def manager?(profile)
    profile && (owner_profile_id == profile.id || memberships.exists?(profile_id: profile.id, role: "admin"))
  end

  validates :audience, inclusion: { in: %w[everyone women men] }

  validates :moderation_state, inclusion: {in: %w[active suspended]}

  private

  def valid_cover
    return unless cover.attached?
    errors.add(:cover, "must be JPEG, PNG, WebP or GIF") unless %w[image/jpeg image/png image/webp image/gif].include?(cover.blob.content_type)
    errors.add(:cover, "must be smaller than 10 MB") if cover.blob.byte_size > 10.megabytes
  end

  def valid_sections
    errors.add(:sections, "must contain unique supported section names") unless sections.is_a?(Array) && sections.uniq == sections && (sections - SECTIONS).empty?
  end
end
