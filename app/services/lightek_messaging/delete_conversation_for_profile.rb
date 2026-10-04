# frozen_string_literal: true

module LightekMessaging
  class DeleteConversationForProfile
    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      profile:,
      at: Time.current
    )
      @conversation =
        conversation

      @profile =
        profile

      @at =
        at
    end

    def call
      unless conversation.direct?
        raise ArgumentError,
              "Only direct conversations can be deleted for a profile"
      end

      member =
        conversation
          .active_participant_for(
            profile
          )

      unless member
        raise AccessDenied,
              "Conversation is unavailable"
      end

      member.update!(
        left_at:
          at
      )

      member
    end

    private

    attr_reader :conversation,
                :profile,
                :at
  end
end
