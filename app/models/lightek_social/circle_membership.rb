# frozen_string_literal: true

module LightekSocial
  class CircleMembership < ApplicationRecord
    self.table_name =
      "lightek_social_circle_memberships"

    belongs_to :circle,
               class_name:
                 "LightekSocial::Circle",
               inverse_of: :memberships

    belongs_to :profile

    validates :profile_id,
              uniqueness: {
                scope:
                  :circle_id
              }

    validate :owner_cannot_be_member

    private

    def owner_cannot_be_member
      return if circle.blank? ||
                profile_id.blank?

      return unless circle.owner_profile_id ==
                    profile_id

      errors.add(
        :profile,
        "cannot be added to its own circle"
      )
    end
  end
end
