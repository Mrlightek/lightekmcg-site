# frozen_string_literal: true

module LightekMessaging
  class Conversation < ApplicationRecord
    self.table_name =
      "lightek_messaging_conversations"

    KINDS =
      %w[
        direct
        group
        community
        watch_party
      ].freeze

    belongs_to :created_by_profile,
               class_name: "Profile"

    has_many :participants,
             -> { order(:id) },
             class_name:
               "LightekMessaging::Participant",
             dependent: :destroy,
             inverse_of: :conversation

    has_many :profiles,
             through: :participants,
             source: :profile

    has_many :messages,
             -> {
               order(
                 :created_at,
                 :id
               )
             },
             class_name:
               "LightekMessaging::Message",
             dependent: :destroy,
             inverse_of: :conversation

    validates :kind,
              presence: true,
              inclusion: {
                in: KINDS
              }

    validates :title,
              length: {
                maximum: 120
              },
              allow_blank: true

    validates :title,
              presence: true,
              if: :group?

    validates :direct_key,
              presence: true,
              uniqueness: true,
              if: :direct?

    validates :direct_key,
              absence: true,
              unless: :direct?

    scope :recent_first,
          -> {
            order(
              Arel.sql(
                "COALESCE(" \
                "last_message_at, " \
                "created_at" \
                ") DESC"
              ),
              id: :desc
            )
          }

    def direct?
      kind == "direct"
    end

    def group?
      kind == "group"
    end

    def community?
      kind == "community"
    end

    def watch_party?
      kind == "watch_party"
    end

    def participant_for(profile)
      participants.find_by(
        profile_id: profile.id
      )
    end

    def active_participant_for(profile)
      participants
        .active
        .find_by(
          profile_id: profile.id
        )
    end
  end
end
