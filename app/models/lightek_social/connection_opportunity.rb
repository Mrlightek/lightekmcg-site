# frozen_string_literal: true

module LightekSocial
  class ConnectionOpportunity < ApplicationRecord
    self.table_name =
      "lightek_social_connection_opportunities"

    STATUSES =
      %w[
        pending
        acted
        dismissed
        expired
      ].freeze

    belongs_to :profile

    belongs_to :related_profile,
               class_name: "Profile"

    belongs_to :context,
               polymorphic: true,
               optional: true

    validates :kind,
              presence: true

    validates :status,
              inclusion: {
                in: STATUSES
              }

    validates :source_key,
              uniqueness: true,
              allow_nil: true

    validate :profiles_must_differ

    scope :pending,
          -> {
            where(
              status:
                "pending"
            )
          }

    def reasons
      Array(
        metadata[
          "reasons"
        ]
      )
    end

    private

    def profiles_must_differ
      return if profile_id.blank? ||
                related_profile_id.blank?

      return unless profile_id ==
                    related_profile_id

      errors.add(
        :related_profile,
        "cannot be yourself"
      )
    end
  end
end
