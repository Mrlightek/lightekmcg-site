class StudioProject < ApplicationRecord
  has_many :productions, dependent: :destroy
  has_many :studio_scenes, dependent: :destroy
  has_many :creation_jobs, through: :studio_scenes
  has_many :studio_operations, dependent: :destroy
  has_many :studio_publications, dependent: :destroy
  has_many :studio_live_operations, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }

  after_create :create_default_scene

  private

  def create_default_scene
    studio_scenes.create!(name: "Scene 1", settings: StudioScene.default_settings)
  end
end
