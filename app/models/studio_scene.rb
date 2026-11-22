class StudioScene < ApplicationRecord
  has_one_attached :blender_bundle
  has_one_attached :blender_source
  has_one_attached :editor_source
  belongs_to :studio_project
  belongs_to :production, optional: true
  has_many :scene_objects, -> { order(:position, :id) }, dependent: :destroy
  has_many :creation_jobs, dependent: :destroy
  has_many :studio_operations, dependent: :nullify
  has_many :studio_workstations, dependent: :destroy

  has_many :studio_scene_renders, dependent: :destroy
  scope :animation_scenes, -> { where.not(scene_spec: nil) }

  before_destroy :ensure_animation_idle, prepend: true, if: :scene_spec?
  validate :valid_animation_spec, if: :scene_spec?

  validates :name, presence: true
  validate :settings_must_be_an_object

  def self.default_settings
    {
      "render_engine" => "BLENDER_EEVEE_NEXT",
      "resolution_x" => 1280,
      "resolution_y" => 720,
      "resolution_percentage" => 100,
      "transparent_background" => false,
      "world_color" => [0.03, 0.03, 0.03, 1.0]
    }
  end

  private

  def ensure_animation_idle
    lock!
    return unless studio_scene_renders.active.exists?
    errors.add(:base, "Wait for this scene’s video renders to finish before deleting it.")
    throw :abort
  end

  def valid_animation_spec
    self.scene_spec = Studio::Animation::SceneSpec.normalize(scene_spec)
  rescue ArgumentError => error
    errors.add(:scene_spec, error.message)
  end

  def settings_must_be_an_object
    errors.add(:settings, "must be a JSON object") unless settings.is_a?(Hash)
  end
end
