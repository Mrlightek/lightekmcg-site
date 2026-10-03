# frozen_string_literal: true

module LightekSocial
  class RelationshipEvent < ApplicationRecord
    self.table_name =
      "lightek_social_relationship_events"

    belongs_to :actor_profile,
               class_name: "Profile"

    belongs_to :target_profile,
               class_name: "Profile"

    belongs_to :context,
               polymorphic: true,
               optional: true

    validates :pair_key,
              presence: true

    validates :event_type,
              presence: true,
              format: {
                with:
                  /\A[a-z0-9_.:-]+\z/
              }

    validates :source_key,
              uniqueness: true,
              allow_nil: true

    validate :profiles_must_differ

    before_validation :assign_pair_key

    scope :strength_signals,
          -> {
            where(
              counts_toward_strength:
                true
            )
          }

    private

    def assign_pair_key
      return if actor_profile_id.blank? ||
                target_profile_id.blank?

      self.pair_key =
        LightekSocial.pair_key(
          actor_profile_id,
          target_profile_id
        )
    end

    def profiles_must_differ
      return if actor_profile_id.blank? ||
                target_profile_id.blank?

      return unless actor_profile_id ==
                    target_profile_id

      errors.add(
        :target_profile,
        "cannot be yourself"
      )
    end
  end
end
