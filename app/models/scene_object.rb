class SceneObject < ApplicationRecord
  TYPES = %w[cube sphere cylinder plane camera point_light sun_light area_light].freeze

  belongs_to :studio_scene

  validates :name, presence: true
  validates :object_type, inclusion: { in: TYPES }
  validates :definition, presence: true
  validate :definition_must_be_an_object

  private

  def definition_must_be_an_object
    errors.add(:definition, "must be a JSON object") unless definition.is_a?(Hash)
  end
end

