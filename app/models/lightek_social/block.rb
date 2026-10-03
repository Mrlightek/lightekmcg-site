# frozen_string_literal: true

module LightekSocial
  class Block < ApplicationRecord
    self.table_name =
      "lightek_social_blocks"

    belongs_to :blocker_profile,
               class_name: "Profile"

    belongs_to :blocked_profile,
               class_name: "Profile"

    validates :blocked_profile_id,
              uniqueness: {
                scope:
                  :blocker_profile_id
              }

    validate :profiles_must_differ

    private

    def profiles_must_differ
      return if blocker_profile_id.blank? ||
                blocked_profile_id.blank?

      return unless blocker_profile_id ==
                    blocked_profile_id

      errors.add(
        :blocked_profile,
        "cannot be yourself"
      )
    end
  end
end
