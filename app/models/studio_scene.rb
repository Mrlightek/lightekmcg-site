class StudioScene < ApplicationRecord
  belongs_to :studio_project
  belongs_to :production, optional: true
  has_many :scene_objects, -> { order(:position, :id) }, dependent: :destroy
  has_many :creation_jobs, dependent: :destroy
  has_many :studio_operations, dependent: :nullify

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

  def settings_must_be_an_object
    errors.add(:settings, "must be a JSON object") unless settings.is_a?(Hash)
  end
end
