class StudioAsset < ApplicationRecord
  belongs_to :owner, class_name: "User"
  belongs_to :site, class_name: "DymondSite::Site", optional: true
  belongs_to :studio_project, optional: true
  has_one_attached :character_photo
  has_one_attached :ai_input
  has_one_attached :performance_driver
  has_one_attached :file
  has_one_attached :bundle
  has_one_attached :native
  has_one_attached :proxy
  has_one_attached :thumbnail
  has_one_attached :pipeline_base
  has_many_attached :pipeline_sidecars
  scope :shared_studio_library, -> { where(animation_role: nil) }
  scope :animation_assets, -> { where.not(animation_role: nil) }
  scope :animation_starters, -> { where(status: "ready").where("metadata ->> 'starter_cast' IS NOT NULL") }

  validates :animation_role, inclusion: { in: %w[character prop background audio viseme] }, allow_nil: true
  validates :dimension_mode, inclusion: { in: %w[2d 2_5d 3d] }, allow_nil: true
  validate :animation_file_format, if: :animation_role?

  ANIMATION_IMAGE_EXTENSIONS = %w[png webp svg].freeze
  ANIMATION_MODEL_EXTENSIONS = %w[glb gltf fbx blend].freeze
  ANIMATION_AUDIO_EXTENSIONS = %w[wav mp3 m4a aac ogg flac].freeze

  def animation_file_format
    formats = case animation_role
    when "audio"
      errors.add(:dimension_mode, "must be blank for audio") if dimension_mode.present?
      ANIMATION_AUDIO_EXTENSIONS
    when "viseme"
      errors.add(:dimension_mode, "must be 2d for mouth artwork") unless dimension_mode == "2d"
      ANIMATION_IMAGE_EXTENSIONS
    else
      errors.add(:dimension_mode, "is required for artwork") if dimension_mode.blank?
      dimension_mode == "3d" ? ANIMATION_MODEL_EXTENSIONS : ANIMATION_IMAGE_EXTENSIONS
    end
    if !file.attached?
      errors.add(:file, "is required")
    elsif !formats.include?(file.filename.extension.to_s.downcase)
      errors.add(:file, "must use one of these extensions: #{formats.join(', ')}")
    elsif file.byte_size > 64.megabytes
      errors.add(:file, "must be 64 MB or smaller")
    end
  end

  validates :name, presence: true, length: { maximum: 160 }
  validates :kind, inclusion: { in: %w[image audio video blend glb] }
  validates :status, inclusion: { in: %w[uploaded processing ready failed] }
  validates :request_key, presence: true, uniqueness: { scope: :owner_id }
  def self.for_actor(access)
    library = shared_studio_library.where("COALESCE(metadata ->> 'network_ad_exchange', '') <> 'reserved'")
      .where("COALESCE(metadata ->> 'broadcast_program_exchange', '') <> 'reserved'")
    return library if access.user.role == "super_admin"
    if access.site_id && %w[admin editor].include?(LightekPwa::Policy.new(user: access.user, site: DymondSite::Site.find(access.site_id)).role)
      return library.where(site_id: access.site_id)
    end
    library.where(owner_id: access.user.id, site_id: access.site_id)
  end
end
