# frozen_string_literal: true

module LightekMessaging
  class Message < ApplicationRecord
    self.table_name =
      "lightek_messaging_messages"

    MESSAGE_TYPES =
      %w[
        text
        system
      ].freeze

    belongs_to :conversation,
               class_name:
                 "LightekMessaging::Conversation",
               inverse_of: :messages

    belongs_to :sender_profile,
               class_name: "Profile"

    belongs_to :reply_to_message,
               class_name:
                 "LightekMessaging::Message",
               optional: true

    has_many :replies,
             class_name:
               "LightekMessaging::Message",
             foreign_key:
               :reply_to_message_id,
             dependent: :nullify,
             inverse_of:
               :reply_to_message

    validates :message_type,
              inclusion: {
                in: MESSAGE_TYPES
              }

    validates :body,
              presence: true,
              length: {
                maximum: 10_000
              }

    validate :sender_is_active_participant
    validate :reply_is_in_same_conversation

    private

    def sender_is_active_participant
      return if conversation.blank? ||
                sender_profile.blank?

      return if conversation
                  .participants
                  .active
                  .exists?(
                    profile_id:
                      sender_profile.id
                  )

      errors.add(
        :sender_profile,
        "must be an active conversation participant"
      )
    end

    def reply_is_in_same_conversation
      return if reply_to_message.blank? ||
                conversation.blank?

      return if reply_to_message
                  .conversation_id ==
                conversation.id

      errors.add(
        :reply_to_message,
        "must belong to the same conversation"
      )
    end
  end
end
