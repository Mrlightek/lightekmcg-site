# frozen_string_literal: true

module LightekSocial
  class Circle < ApplicationRecord
    self.table_name =
      "lightek_social_circles"

    belongs_to :owner_profile,
               class_name: "Profile"

    has_many :memberships,
             class_name:
               "LightekSocial::CircleMembership",
             dependent: :destroy,
             inverse_of: :circle

    has_many :profiles,
             through: :memberships

    validates :name,
              presence: true,
              length: {
                maximum: 80
              }

    validates :name_key,
              presence: true,
              uniqueness: {
                scope:
                  :owner_profile_id
              }

    before_validation :normalize_name_key

    private

    def normalize_name_key
      self.name_key =
        name
          .to_s
          .strip
          .downcase
          .gsub(
            /[^a-z0-9]+/,
            "-"
          )
          .gsub(
            /\A-|-?\z/,
            ""
          )
    end
  end
end
