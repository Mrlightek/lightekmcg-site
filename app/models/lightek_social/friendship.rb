# frozen_string_literal: true

module LightekSocial
  class Friendship < ApplicationRecord
    self.table_name =
      "lightek_social_friendships"

    STATUSES =
      %w[
        pending
        accepted
        declined
        cancelled
        ended
      ].freeze

    belongs_to :requester_profile,
               class_name: "Profile"

    belongs_to :addressee_profile,
               class_name: "Profile"

    validates :status,
              inclusion: {
                in: STATUSES
              }

    validates :pair_key,
              presence: true,
              uniqueness: true

    validate :profiles_must_differ

    before_validation :assign_pair_key

    scope :accepted,
          -> {
            where(
              status:
                "accepted"
            )
          }

    def involves?(profile)
      id =
        LightekSocial.profile_id(
          profile
        )

      requester_profile_id == id ||
        addressee_profile_id == id
    end

    def other_profile_for(profile)
      id =
        LightekSocial.profile_id(
          profile
        )

      case id
      when requester_profile_id
        addressee_profile
      when addressee_profile_id
        requester_profile
      else
        nil
      end
    end

    private

    def assign_pair_key
      return if requester_profile_id.blank? ||
                addressee_profile_id.blank?

      self.pair_key =
        LightekSocial.pair_key(
          requester_profile_id,
          addressee_profile_id
        )
    end

    def profiles_must_differ
      return if requester_profile_id.blank? ||
                addressee_profile_id.blank?

      return unless requester_profile_id ==
                    addressee_profile_id

      errors.add(
        :addressee_profile,
        "cannot be yourself"
      )
    end
  end
end
