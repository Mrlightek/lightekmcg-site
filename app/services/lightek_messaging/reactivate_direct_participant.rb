# frozen_string_literal: true

module LightekMessaging
  class ReactivateDirectParticipant
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
              "Only direct conversations can reactivate participants"
      end

      member =
        conversation
          .participant_for(
            profile
          )

      unless member
        raise AccessDenied,
              "Profile is not part of this conversation"
      end

      return member if member.active?

      member.update!(
        joined_at:
          at,

        left_at:
          nil,

        last_read_at:
          nil
      )

      member
    end

    private

    attr_reader :conversation,
                :profile,
                :at
  end
end
