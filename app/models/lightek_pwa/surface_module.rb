module LightekPwa
  class SurfaceModule < ApplicationRecord
    self.table_name =
      "lightek_pwa_surface_modules"

    belongs_to :surface,
               class_name: "LightekPwa::Surface"

    validates :key,
              presence: true

    validates :module_type,
              presence: true

    validates :key,
              uniqueness: {
                scope: :surface_id
              }

    def bootstrap_payload
      {
        id: id,
        key: key,
        type: module_type,
        label: label,
        position: position,
        data_source: data_source,
        capability: capability,
        configuration: configuration
      }
    end
  end
end
