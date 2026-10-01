module LightekPwa
  class Surface < ApplicationRecord
    self.table_name = "lightek_pwa_surfaces"

    has_many :modules,
             -> { order(:position, :id) },
             class_name: "LightekPwa::SurfaceModule",
             foreign_key: :surface_id,
             dependent: :destroy

    validates :key,
              presence: true,
              uniqueness: true

    validates :surface_type,
              presence: true

    validates :label,
              presence: true

    scope :enabled,
          -> { where(enabled: true) }

    scope :ordered,
          -> { order(:position, :id) }

    def bootstrap_payload
      {
        id: id,
        key: key,
        type: surface_type,
        label: label,
        position: position,
        enabled: enabled,
        configuration: configuration,
        modules:
          modules
            .select(&:enabled?)
            .map(&:bootstrap_payload)
      }
    end
  end
end
