# frozen_string_literal: true

module LightekSocial
  class Follow < ApplicationRecord
    self.table_name =
      "lightek_social_follows"

    belongs_to :follower_profile,
               class_name: "Profile"

    belongs_to :followed_profile,
               class_name: "Profile"

    validates :followed_profile_id,
              uniqueness: {
                scope:
                  :follower_profile_id
              }

    validate :profiles_must_differ

    private

    def profiles_must_differ
      return if follower_profile_id.blank? ||
                followed_profile_id.blank?

      return unless follower_profile_id ==
                    followed_profile_id

      errors.add(
        :followed_profile,
        "cannot be yourself"
      )
    end
  end
end
