class StudioProject < ApplicationRecord
  belongs_to :owner, class_name: "User", optional: true
  belongs_to :site, class_name: "DymondSite::Site", optional: true
  has_many :productions, dependent: :destroy
  has_many :studio_scenes, dependent: :destroy
  has_many :studio_assets, dependent: :nullify
  has_many :creation_jobs, through: :studio_scenes
  has_many :studio_operations, dependent: :destroy
  has_many :studio_publications, dependent: :destroy
  has_many :studio_live_operations, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }

  before_destroy :ensure_inactive_before_deletion, prepend: true
  after_create :create_default_scene

  private

  def ensure_inactive_before_deletion
    message = if studio_operations.where(status: %w[pending running]).exists? || creation_jobs.where(status: %w[pending running]).exists? || studio_assets.where(status: %w[uploaded processing]).exists?
      "Wait for queued renders, exports and media processing to finish before deleting this project."
    elsif studio_live_operations.where(status: %w[scheduled connecting live ending]).exists?
      "End or cancel this project's broadcasts before deleting it."
    elsif studio_publications.where(status: %w[scheduled publishing]).exists?
      "Cancel scheduled releases or wait for publishing to finish before deleting this project."
    elsif defined?(StudioWorkstation) && StudioWorkstation.table_exists? && StudioWorkstation.where(studio_scene_id: studio_scenes.select(:id), status: %w[starting building ready saving]).exists?
      "Close this project's native workstation before deleting it."
    end
    return unless message
    errors.add(:base, message)
    throw :abort
  end

  def create_default_scene
    studio_scenes.create!(name: "Scene 1", settings: StudioScene.default_settings)
  end
end
