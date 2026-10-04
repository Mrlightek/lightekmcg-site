# frozen_string_literal: true

module LightekMessaging
  class SendMessage
    def self.call(
      conversation:,
      sender_profile:,
      body:,
      reply_to_message: nil,
      message_type: "text",
      metadata: {}
    )
      new(
        conversation: conversation,
        sender_profile:
          sender_profile,
        body: body,
        reply_to_message:
          reply_to_message,
        message_type:
          message_type,
        metadata: metadata
      ).call
    end

    def initialize(
      conversation:,
      sender_profile:,
      body:,
      reply_to_message:,
      message_type:,
      metadata:
    )
      @conversation =
        conversation

      @sender_profile =
        sender_profile

      @body =
        body.to_s

      @reply_to_message =
        reply_to_message

      @message_type =
        message_type.to_s

      @metadata =
        metadata.to_h
    end

    def call
      authorize_sender!
      authorize_direct_relationship!

      Message.transaction do
        message =
          Message.create!(
            conversation:
              conversation,
            sender_profile:
              sender_profile,
            body: body,
            reply_to_message:
              reply_to_message,
            message_type:
              message_type,
            metadata:
              metadata
          )

        conversation.update!(
          last_message_at:
            message.created_at
        )

        message
      end
    end

    private

    attr_reader :conversation,
                :sender_profile,
                :body,
                :reply_to_message,
                :message_type,
                :metadata

    def authorize_sender!
      return if conversation
                  .participants
                  .active
                  .exists?(
                    profile_id:
                      sender_profile.id
                  )

      raise AccessDenied,
            "Profile is not an active " \
            "participant in this conversation"
    end

    def authorize_direct_relationship!
      return unless conversation.direct?

      peer =
        conversation
          .participants
          .active
          .includes(
            :profile
          )
          .where
          .not(
            profile_id:
              sender_profile.id
          )
          .first
          &.profile

      return unless peer

      return unless LightekSocial.blocked_between?(
        sender_profile,
        peer
      )

      raise AccessDenied,
            "Messaging is unavailable for this blocked relationship"
    end
  end
end
