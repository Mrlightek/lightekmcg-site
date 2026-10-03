# frozen_string_literal: true

module LightekSocial
  class RelationshipStrength < ApplicationRecord
    self.table_name =
      "lightek_social_relationship_strengths"

    METRICS =
      %i[
        reciprocity
        continuity
        context_diversity
        shared_experience
        recency
        confidence
      ].freeze

    belongs_to :profile_a,
               class_name: "Profile"

    belongs_to :profile_b,
               class_name: "Profile"

    validates :pair_key,
              presence: true,
              uniqueness: true

    METRICS.each do |metric|
      validates metric,
                numericality: {
                  greater_than_or_equal_to:
                    0,
                  less_than_or_equal_to:
                    1
                }
    end

    validate :profiles_must_differ

    before_validation :canonicalize_pair

    def overall
      values =
        [
          reciprocity,
          continuity,
          context_diversity,
          shared_experience,
          recency
        ].map(&:to_f)

      return 0.0 if values.empty?

      (
        values.sum /
        values.length
      ).round(4)
    end

    private

    def canonicalize_pair
      return if profile_a_id.blank? ||
                profile_b_id.blank?

      left,
      right =
        LightekSocial.pair_ids(
          profile_a_id,
          profile_b_id
        )

      self.profile_a_id =
        left

      self.profile_b_id =
        right

      self.pair_key =
        "#{left}:#{right}"
    end

    def profiles_must_differ
      return if profile_a_id.blank? ||
                profile_b_id.blank?

      return unless profile_a_id ==
                    profile_b_id

      errors.add(
        :profile_b,
        "cannot be yourself"
      )
    end
  end
end
