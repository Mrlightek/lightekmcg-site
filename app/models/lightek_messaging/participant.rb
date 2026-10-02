# frozen_string_literal: true

module LightekMessaging
  class Participant < ApplicationRecord
    self.table_name =
      "lightek_messaging_participants"

    ROLES =
      %w[
        owner
        admin
        member
      ].freeze

    belongs_to :conversation,
               class_name:
                 "LightekMessaging::Conversation",
               inverse_of: :participants

    belongs_to :profile

    validates :role,
              inclusion: {
                in: ROLES
              }

    validates :profile_id,
              uniqueness: {
                scope: :conversation_id
              }

    validate :left_at_not_before_joined_at

    scope :active,
          -> {
            where(
              left_at: nil
            )
          }

    def active?
      left_at.nil?
    end

    def owner?
      role == "owner"
    end

    def admin?
      role.in?(
        %w[
          owner
          admin
        ]
      )
    end

    def mark_read!(at: Time.current)
      update!(
        last_read_at: at
      )
    end

    private

    def left_at_not_before_joined_at
      return if left_at.blank? ||
                joined_at.blank?

      return if left_at >= joined_at

      errors.add(
        :left_at,
        "cannot be before joined_at"
      )
    end
  end
end
