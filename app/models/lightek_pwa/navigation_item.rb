module LightekPwa
  class NavigationItem < ApplicationRecord
    self.table_name =
      "lightek_pwa_navigation_items"

    validates :key,
              presence: true,
              uniqueness: true

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
        label: label,
        surface_id: surface_key,
        href: href,
        placement: placement,
        position: position,
        requires_capability:
          requires_capability,
        configuration:
          configuration
      }
    end
  end
end
